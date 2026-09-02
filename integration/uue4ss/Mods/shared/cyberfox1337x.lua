local signature = {}

signature["function"] = function(module_name)
    assert(type(module_name) == "string" and module_name ~= "", "module_name must be a non-empty string")
    return module_name
end

signature["function"]("cyberfox1337x")

return signature
