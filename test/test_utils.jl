function http_status_error_mock(code::Integer)
    request = HTTP.Messages.Request("GET", "https://pkg.julialang.org")
    response = HTTP.Messages.Response(Int(404); request=request)
    status_error = HTTP.ExceptionRequest.StatusError(Int16(code), response)
end
