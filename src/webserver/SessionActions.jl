module SessionActions

import ..Pluto: ServerSession, ClientSession, Notebook, emptynotebook, tamepath, new_notebooks_directory, without_dotjl, numbered_until_new, readwrite, move_notebook!, update_save_run!, putnotebookupdates!, putplutoupdates!, load_notebook, clientupdate_notebook_list, WorkspaceManager, @asynclog

struct NotebookIsRunningException <: Exception
    notebook::Notebook
end

abstract type AbstractUserError <: Exception end
struct UserError <: AbstractUserError
    msg::String
end
function Base.showerror(io::IO, e::UserError)
    print(io, e.msg)
end

function open_url(session::ServerSession, url::AbstractString; kwargs...)
    path = download(url, emptynotebook().path)
    open(session, path; kwargs...)
end

function open(session::ServerSession, path::AbstractString; run_async=true, compiler_options=nothing, as_sample=false)
    if as_sample
        new_filename = "sample " * without_dotjl(basename(path))
        new_path = numbered_until_new(joinpath(new_notebooks_directory(), new_filename); suffix=".jl")
        
        readwrite(path, new_path)
        path = new_path
    end

    for nb in values(session.notebooks)
        if realpath(nb.path) == realpath(tamepath(path))
            throw(NotebookIsRunningException(nb))
        end
    end
    
    nb = load_notebook(tamepath(path), session.options.evaluation.run_notebook_on_load)

    # overwrites the notebook environment if specified
    if compiler_options !== nothing
        nb.compiler_options = compiler_options
    end

    session.notebooks[nb.notebook_id] = nb
    if session.options.evaluation.run_notebook_on_load
        update_save_run!(session, nb, nb.cells; run_async=run_async, prerender_text=true)
        # TODO: send message when initial run completed
    end

    if run_async
        @asynclog putplutoupdates!(session, clientupdate_notebook_list(session.notebooks))
    else
        putplutoupdates!(session, clientupdate_notebook_list(session.notebooks))
    end

    nb
end

function new(session::ServerSession; run_async=true)
    nb = emptynotebook()
    update_save_run!(session, nb, nb.cells; run_async=run_async, prerender_text=true)
    session.notebooks[nb.notebook_id] = nb

    if run_async
        @asynclog putplutoupdates!(session, clientupdate_notebook_list(session.notebooks))
    else
        putplutoupdates!(session, clientupdate_notebook_list(session.notebooks))
    end

    nb
end

function shutdown(session::ServerSession, notebook::Notebook; keep_in_session=false, async=false)
    if !keep_in_session
        listeners = putnotebookupdates!(session, notebook) # TODO: shutdown message
        delete!(session.notebooks, notebook.notebook_id)
        putplutoupdates!(session, clientupdate_notebook_list(session.notebooks))
        for client in listeners
            @async close(client.stream)
        end
    end
    WorkspaceManager.unmake_workspace((session, notebook); async=async)
end

function attach_client(session::ServerSession, clientid::Symbol, stream::IO)
  client = get(session.connected_clients, clientid, nothing)
  if client === nothing
    client = ClientSession(clientid, stream)
    session.connected_clients[clientid] = client
    @info "Client connected $(clientid) (total $(length(session.connected_clients)))"
  else
    client.stream = stream # it might change when the same client reconnects
  end
  client
end

function detach_client(session::ServerSession, client::ClientSession)
  @info "Client disconnected $(client.id)"
  delete!(session.connected_clients, client.id)
  if client.connected_notebook !== nothing
    notebook = client.connected_notebook

    # cleanup client-owned cells
    to_remove = []
    for (cellid, cell) in notebook.cells_dict
      if cell.owner == client.id
        push!(to_remove, cellid)
      end
    end
    if !isempty(to_remove)
      for cellid in to_remove
        delete!(notebook.cells_dict, cellid)
      end
      notebook.cell_order = filter(
        cellid -> haskey(notebook.cells_dict, cellid),
        notebook.cell_order
      )
      # TODO(andreypopp): do we want to do that here?
      # update_save_run!(session, notebook, notebook.cells; run_async=true, save=false)
    end
  end
end

end
