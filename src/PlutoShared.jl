"""
This module is shared between the server and notebook processes.

It contains several data types definitions which should be understood on both
end by the serialization machinery.
"""
module PlutoShared

"""
Data structure which reprensets a single element of a User Interface.

Accidentally this was made to match the representation of React elements (the
data structure produced by React.createElement(...) or JSX syntax).
"""
struct UI
  type::String
  props::Dict{Symbol,Any}
end

UI(type::String; kwargs...) =
  UI(type, Dict(kwargs...))

end
