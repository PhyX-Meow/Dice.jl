function xdy(num::Integer, face::Integer)
    if num <= 0 || face <= 0
        throw(DiceError("悟理球无法骰不存在的骰子！"))
    end
    if num >= 1 << 16
        throw(DiceError("骰子太多了，骰不过来了qwq"))
    end
    if face >= 1 << 16
        throw(DiceError("你这骰子已经是个球球了，没法骰了啦！"))
    end
    rand(1:face, num) |> sum
end

function rollDice(str::AbstractString)
    expr = replace(str, r"[^0-9d\(\)\+\-\*/]" => "")
    if isempty(expr)
        return ("1d100", xdy(1, 100))
    end
    if match(r"d\d*d", expr) !== nothing
        throw(DiceError("表达式格式错误，看看是不是两个xdy贴在一起了？"))
    end
    expr = replace(expr, r"(?<!\d)d" => "1d")
    expr = replace(expr, r"d(?!\d)" => "d100")
    expr_ = replace(expr, r"(\d*)d(\d*)" => s"xdy(\1,\2)", "/" => "÷")
    return (expr, Meta.parse(expr_) |> eval)
end

function skillCheck(success::Int, rule::Symbol, bonus::Int)
    if success >= 1 << 16
        throw(DiceError("错误，成功率不合基本法"))
    end

    fate = rand(1:100)
    res = "1d100 = $(fate)"

    if bonus != 0
        r = fate % 10
        bDice = rand(0:9, abs(bonus))
        bFate = @. bDice * 10 + r
        replace!(bFate, 0 => 100)
        if bonus > 0
            fate = min(fate, minimum(bFate))
            res *= "，奖励骰：$(bDice) = $(fate)"
        else
            fate = max(fate, maximum(bFate))
            res *= "，惩罚骰：$(bDice) = $(fate)"
        end
    end

    check = :na
    if rule == :book
        check = @match fate begin
            1 => :critical
            100 => :fumble
            if success < 50
            end && GuardBy(>=(96)) => :fumble
            GuardBy(<=(success ÷ 5)) => :extreme
            GuardBy(<=(success ÷ 2)) => :hard
            GuardBy(<=(success)) => :regular
            _ => :failure
        end
    end
    if rule == :pop
        check = @match fate begin
            1:5 => :critical
            96:100 => :fumble
            GuardBy(<=(success ÷ 5)) => :extreme
            GuardBy(<=(success ÷ 2)) => :hard
            GuardBy(<=(success)) => :regular
            _ => :failure
        end
    end
    if check == :na
        throw(DiceError("错误，找不到对应的规则"))
    end
    res *= "/$(success)。" * rand(diceDefault.customReply[check])
    return res
end

function roll(argstr; groupId = "", kw...)
    ops, b, p, str = argstr
    if ops === nothing
        ops = ""
    end
    bonus = 0
    hidden = 'h' ∈ ops
    book = 'c' ∈ ops
    pop = 'a' ∈ ops
    check = pop || book
    if b !== nothing
        bonus = 1
        if b != ""
            bonus = parse(Int, b)
        end
        check = true
        if p !== nothing
            return DiceReply("人不能同时骰奖励骰和惩罚骰，至少不该。")
        end
    end
    if p !== nothing
        bonus = -1
        if p != ""
            bonus = -parse(Int, p)
        end
        check = true
    end

    if check
        rule = groupDefault.rcRule
        if !isempty(groupId) && haskey(groupConfigs, groupId)
            rule = groupConfigs[groupId].rcRule
        end
        if pop
            rule = :pop
        elseif book
            rule = :book
        end

        success = 1
        patt = [r"\s(\d+)$", r"^(\d+)\s", r"(\d+)$", r"^(\d+)"]
        for p ∈ patt
            m = match(p, str)
            if m !== nothing
                success = parse(Int, m.captures[1])
                return DiceReply(skillCheck(success, rule, bonus), hidden, true)
            end
        end
        word = match(r"^([^\s\d]*)", str)
        if word !== nothing
            skill = word.captures[1]
            if haskey(skillList, skill)
                success = skillList[skill]
            end
        end
        return DiceReply(skillCheck(success, rule, bonus), hidden, true)
    end
    expr, res = rollDice(str)
    return DiceReply("你骰出了 $expr = $res", hidden, true)
end

const charaTemplate = quote
    """
    力量:$str 敏捷:$dex 意志:$pow
    体质:$con 外貌:$app 教育:$edu
    体型:$siz 智力:$int 幸运:$luc
    HP:$hp MP:$mp DB:$db MOV:$mov
    总和:$total/$luc_total
    """
end

randChara = @eval function ()
    str = xdy(3, 6) * 5
    con = xdy(3, 6) * 5
    siz = (xdy(2, 6) + 6) * 5
    dex = xdy(3, 6) * 5
    app = xdy(3, 6) * 5
    int = (xdy(2, 6) + 6) * 5
    pow = xdy(3, 6) * 5
    edu = (xdy(2, 6) + 6) * 5
    luc = xdy(3, 6) * 5
    total = str + con + siz + dex + app + int + pow + edu
    luc_total = total + luc
    hp = (con + siz) ÷ 10
    mp = pow ÷ 5
    mov = 8
    if str > siz && dex > siz
        mov = 9
    elseif str <= siz && dex <= siz
        mov = 7
    end
    db = @match str + siz begin
        GuardBy(<(2)) => "N/A"
        GuardBy(<(65)) => "-2"
        GuardBy(<(85)) => "-1"
        GuardBy(<(124)) => "0"
        GuardBy(<(165)) => "1d4"
        x => begin
            n = 1 + (x - 165) ÷ 80
            "$(n)d6"
        end
    end
    $charaTemplate
end

function charMake(argstr; kw...)
    m = match(r"^\s*(\d+)", argstr[1])
    num = 1
    if m !== nothing
        num = parse(Int, m.captures[1])
    end
    if num > 10
        return DiceReply("单次人物做成最多 10 个哦，再多算不过来了")
    end
    if num <= 0
        return DiceReply("啊咧，你要捏几个人来着")
    end
    res = [randChara() for i ∈ 1:num]
    res[1] = "7 版人物做成：\n" * res[1]
    return DiceReply(res, false, false)
end

function botStart(args; kw...)
    return DiceReply("你现在也是手上粘着悟理球的 Friends 啦！", false, false)
end

function botInfo(args; kw...)
    return DiceReply("""
        Dice Julian, made by 悟理(@phyxmeow).
        Version $diceVersion
        输入 .help 获取指令列表
        """, false, false)
end

function botSwitch(argstr; groupId = "", kw...)
    if isempty(groupId)
        return noReply
    end
    if !haskey(groupConfigs, groupId)
        groupConfigs[groupId] = groupDefault
    end
    cp = groupConfigs[groupId]
    @switch argstr[1] begin
        @case "on"
        if groupConfigs[groupId].isOff
            cp.isOff = false
            delete!(groupConfigs, groupId)
            groupConfigs[groupId] = cp
            return DiceReply("悟理球出现了！")
        end
        return DiceReply("悟理球已经粘在你的手上了，要再来一个吗")
        @case "off"
        if groupConfigs[groupId].isOff
            return noReply
        end
        cp.isOff = true
        delete!(groupConfigs, groupId)
        groupConfigs[groupId] = cp
        return DiceReply("悟理球不知道哪里去了~")
        @case "exit"
        sendMessage(text = "悟理球从这里消失了", chat_id = parse(Int, groupId))
        leaveChat(chat_id = parse(Int, groupId))
        delete!(groupConfigs, groupId)
        return noReply
    end
    return noReply
end

function diceHelp(argstr; kw...)
    return DiceReply("喵喵喵", false, false)
end

function getJrrpSeed()
    resp = HTTP.get("https://qrng.anu.edu.au/API/jsonI.php?length=1&type=hex16&size=8", readtimeout = 1)
    # 加入超时报错
    dataJSON = resp.body |> String |> JSON3.read
    if !dataJSON.success
        throw(DiceError("今日人品获取失败"))
    end
    return parse(UInt64, dataJSON.data[1], base = 16)
end

function jrrp(argstr; userId = "", kw...)
    date = today() |> string
    if haskey(jrrpCache, date)
        seed = jrrpCache[date]
    else
        seed = getJrrpSeed()
        jrrpCache[date] = seed
    end
    rng = MersenneTwister(parse(UInt64, userId) ⊻ seed)
    rp = rand(rng, 1:100)
    return DiceReply("今天你的手上粘了 $rp 个悟理球！")
end

function fuck2060(args...)
    return DiceReply("玩你🐎透明字符呢，滚！", false, true)
end