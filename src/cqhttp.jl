function run_bot(f::Function, cq_server::AbstractString, port::Integer)
    WebSockets.open("ws://$cq_server:$port") do ws
        for str in ws
            json_str = JSON3.read(str)
            try
                f(ws, json_str)
            catch err
                @error err
                if err isa InterruptException
                    break
                end
            end
        end
    end
end