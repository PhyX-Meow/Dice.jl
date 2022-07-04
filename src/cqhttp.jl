function run_bot(f::Function)
    cq_ws_server = get(ENV, "CQ_WS_SERVER", "")
    WebSockets.open(cq_ws_server) do ws
        for str ∈ ws
            msg = JSON3.read(str)
            try
                f(ws, msg)
            catch err
                @error err
                if err isa InterruptException
                    break
                end
            end
        end
    end
end