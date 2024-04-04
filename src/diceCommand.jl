macro dice_str(str)
    :(rollDice($str).total)
end

function skillCheck(success::Int, rule::Symbol, bonus::Int)
    if success > 512
        throw(DiceError("错误，成功率不合基本法"))
    end

    fate = rand(rng_state[], 1:100)
    res = "1d100 = $(fate)"

    if bonus != 0
        r = fate % 10
        bDice = rand(rng_state[], 0:9, abs(bonus))
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

    check = :unknown
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
    res *= "/$(success)。"
    return res, check # 重构这里的代码
end

function roll(msg, args) # Only COC check for now
    userId = msg.userId
    options, str = args
    isHidden = 'h' ∈ options

    if match(r"[acbp]", options) === nothing
        defaultDice = getConfig(msg.groupId, msg.userId, "defaultDice")
        isDetailed = getConfig(msg.groupId, msg.userId, "detailedDice")

        # Extract comment
        m_comment = if match(r"\s", str) !== nothing
            match(r"\s(\S*?[^0-9dD()+\-*/#\s][\s\S]*)", str)
        else
            match(r"([^0-9dD()+\-*/#\s][\s\S]*)", str)
        end
        comment = isnothing(m_comment) ? "" : m_comment.captures[1]
        str = replace(isnothing(m_comment) ? str : SubString(str, 1, m_comment.offset), r"\s" => "")

        # Extract number of times
        m = match(r"([0-9dD()+\-*/]*)(#\d+)?", str)
        expr_str = m.captures[1]
        num_str = m.captures[2]
        num = 1
        if num_str !== nothing
            num = parse(Int, num_str[2:end])
        end
        num > 42 && throw(DiceError("骰子太多了，骰不过来了qwq"))

        resultIRs = rollDice(expr_str; defaultDice = defaultDice, times = num)
        reply_str = "你骰出了"
        if isDetailed
            for (i, L) ∈ pairs(resultIRs)
                reply_str *= num > 1 ? "\n#$(i)：" : " "
                reply_str *= "$(L.expr) = "
                if 'd' ∈ L.expr && match(r"^\[\d*\]$", L.result) === nothing
                    reply_str *= "$(L.result) = "
                end
                reply_str *= string(L.total)
            end
        else
            reply_str *= " " * resultIRs[1].expr
            reply_str *= num > 1 ? "#$num = " * string(map(L -> L.total, resultIRs)) : " = " * string(resultIRs[1].total)
        end
        @reply(reply_str, isHidden, true)
    end

    book = 'c' ∈ options
    pop = 'a' ∈ options
    book && pop && @reply("检定不能同时使用两种规则，至少不该。")
    rule = pop ? :pop : :book

    bonus = 0
    for m ∈ eachmatch(r"(\d*)([bp])", options)
        num = isempty(m.captures[1]) ? 1 : parse(Int, m.captures[1])
        if m.captures[2] == "p"
            num = -num
        end
        bonus += num
    end

    # Extract number of times
    m = match(r"([^#]*)(#\d+)?", str)
    check_str = m.captures[1]
    num_str = m.captures[2]
    num = 1
    if num_str !== nothing
        num = parse(Int, num_str[2:end])
    end
    num > 42 && throw(DiceError("骰子太多了，骰不过来了qwq"))

    success = 1
    patt = [r"\s(\d+)$", r"^(\d+)\s", r"(\d+)$", r"^(\d+)"]
    for p ∈ patt
        m = match(p, check_str)
        if m !== nothing
            success = parse(Int, m.captures[1])
            @goto _do_check_
        end
    end
    word = match(r"^([^\s\d]+)", check_str)
    if word !== nothing
        skill = word.captures[1] |> lowercase
        if haskey(skillAlias, skill)
            skill = skillAlias[skill]
        end
        if haskey(defaultSkill, skill)
            success = defaultSkill[skill]
        end
        if haskey(userData[userId], " select")
            name = userData[userId][" select"]
            inv = userData[userId][name]
            if haskey(inv, skill)
                success = inv[skill]
            end
        end
    end

    @label _do_check_
    reply_str = ""
    for i ∈ 1:num
        i > 1 && (reply_str *= "\n")
        res, check = skillCheck(success, rule, bonus)
        reply_str *= num > 1 ? "#$(i)：" : ""
        reply_str *= res
        reply_str *= num > 1 ? checkReplySimple[check] : rand(checkReply[check])
    end
    @reply(reply_str, isHidden, true)
end

function rollDice(str::AbstractString; defaultDice = 100, lead = false, times = 1, strict_calculate = false)
    str = replace(str, "D" => "d")
    if isempty(str)
        str = strict_calculate ? "0" : "1d$defaultDice"
    end
    if !strict_calculate && str[1] ∈ "+-*/"
        str = "1d$defaultDice" * str
    end
    if match(r"d\d*d", str) !== nothing
        throw(DiceError("表达式有歧义，看看是不是有写出了XdYdZ样子的算式？"))
    end
    str = replace(str, r"(?<![\d)])d" => "1d")
    str = replace(str, r"d(?![\d(])" => "d$defaultDice")

    try
        if lead
            result = replace(str, "d" => "↓", "/" => "÷") |> Meta.parse |> eval
            return [DiceIR(str, string(result), result, dice_op_precedence[:num])]
        end
        expr = replace(str, "d" => "↑", "/" => "÷") |> Meta.parse
        _expr_ = expr_replace(expr, x -> x isa Int, x -> :(DiceIR($x)); skip = x -> (x.head == :call && x.args[1] == :↑))
        return [eval(_expr_) for _ ∈ 1:times]
    catch err
        err isa DiceError && rethrow()
        showerror(stdout, err)
        println()
        if debug_flag
            display(stacktrace(catch_backtrace()))
            println()
        end
        throw(DiceError("表达式格式错误，算不出来惹"))
    end
end

function sanCheck(msg, args) # To do: 恐惧症/躁狂症
    userId = msg.userId
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 `.pc 人物姓名` 选择人物卡或使用 `.new 姓名-属性列表` 创建人物卡"))
    end

    str = args[1]
    str = replace(str, r"\s" => "")
    m = match(r"([d\d+\-*]+)/([d\d+\-*]+)", str)
    if m === nothing
        throw(DiceError("表达式格式错误，算不出来惹"))
    end
    succ, fail = m.captures

    name = userData[userId][" select"]
    inv = userData[userId][name]
    if haskey(inv, "理智")
        san = inv["理智"]
    elseif haskey(inv, "意志")
        san = inv["意志"]
    else
        throw(DiceError("错误，没有找到当前角色的理智值，是不是已经疯了？"))
    end
    if san == 0
        @reply("不用检定了，$name 已经永久疯狂了。")
    end

    sanMax = 99
    if haskey(inv, "克苏鲁神话")
        sanMax -= inv["克苏鲁神话"]
    end

    res, check = skillCheck(san, :book, 0)
    res = "$name 的理智检定：" * res
    @switch check begin
        @case :critical
        resultIR = rollDice(succ, strict_calculate = true)[1]
        res *= "大成功！\n显然这点小事完全无法撼动你钢铁般的意志\n"

        @case :fumble
        resultIR = rollDice(fail; lead = true, strict_calculate = true)[1]
        res *= "大失败！\n朝闻道，夕死可矣。\n"

        @case :failure
        resultIR = rollDice(fail, strict_calculate = true)[1]
        res *= "失败\n得以一窥真实的你陷入了不可名状的恐惧，看来你的“觉悟”还不够呢\n"

        @case _
        resultIR = rollDice(succ, strict_calculate = true)[1]
        res *= "成功\n真正的调查员无畏觅见真实！可是捱过了这次，还能捱过几次呢？\n"
    end
    expr = resultIR.expr
    loss = resultIR.total
    san = max(0, san - loss)
    res *= "理智损失：$(expr) = $(loss)，当前剩余理智：$(san)/$(sanMax)"
    if san == 0
        res *= "\n调查员已陷入永久疯狂。"
    elseif loss >= 5
        res *= "\n单次理智损失超过 5 点，调查员已陷入临时性疯狂，使用 .ti/.li 可以获取随机疯狂发作症状"
    end
    setJLD!(inv, "理智" => san, "SaveTime" => now())
    @reply(res)
end

function skillEn(msg, args)
    userId = msg.userId
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 `.pc 人物姓名` 选择人物卡或使用 `.new 姓名-属性列表` 创建人物卡"))
    end
    str = args[1]
    word = match(r"^([^\s\d]+)", str)
    name = userData[userId][" select"]
    if word === nothing
        throw(DiceError("不知道你要成长啥子诶……"))
    end
    skill = word.captures[1] |> lowercase
    if haskey(skillAlias, skill)
        skill = skillAlias[skill]
    end
    inv = userData[userId][name]
    if haskey(inv, skill)
        success = inv[skill]
    elseif haskey(defaultSkill, skill)
        success = defaultSkill[skill]
    else
        throw(DiceError("$name 好像没有 $(skill) 这个技能耶"))
    end
    fate = rand(rng_state[], 1:100)
    if fate <= success
        @reply("1d100 = $(fate)/$(success)\n失败了，什么事情都没有发生.jpg")
    end

    up = rand(rng_state[], 1:10)
    setJLD!(inv, skill => success + up, "SaveTime" => now())

    @reply(
        """
        1d100 = $(fate)/$(success)
        成功！$name 的 $skill 成长：
        1d10 = $(up)，$success => $(success+up)\
        """
    )
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

function charMakeDnd(msg, args)
    m = match(r"^\s*(\d+)", args[1])
    num = isnothing(m) ? 1 : parse(Int, m.captures[1])
    num > 10 && @reply("单次人物做成最多 10 个哦，再多算不过来了")
    num <= 0 && @reply("啊咧，你要捏几个人来着")

    res = "DND5e 人物做成："
    for _ in 1:num
        stats = sort([xdy(4, 6; take = 3) for _ ∈ 1:6]; rev = true)
        res = res * "\n" * string(stats) * "，总和：" * string(sum(stats))
    end
    @reply(res, false, false)
end

function charMake(msg, args)
    m = match(r"^\s*(\d+)", args[1])
    num = isnothing(m) ? 1 : parse(Int, m.captures[1])
    num > 10 && @reply("单次人物做成最多 10 个哦，再多算不过来了")
    num <= 0 && @reply("啊咧，你要捏几个人来着")

    res = [randChara() for _ ∈ 1:num]
    res[1] = "7 版人物做成：\n" * res[1]
    for str ∈ res
        DiceReply(str, false, false)(msg)
    end
end

function botStart(msg, args)
    @reply("你现在也是手上粘着悟理球的 Friends 啦！", false, false)
end

function botInfo(msg, args)
    @reply(
        """
        Dice Julian, made by 悟理(@phyxmeow).
        Version $diceVersion
        项目主页：https://github.com/PhyX-Meow/Dice.jl
        输入 .help 获取指令列表\
        """,
        false,
        false,
    )
end

function diceHelp(msg, args)
    m = match(r"link", args[1])
    m !== nothing && @reply(helpLinks, false, false)
    @reply(helpText, false, false)
end

function botSwitch(msg, args)
    userId = msg.userId
    groupId = msg.groupId
    config = getConfig!(groupId, userId)
    @switch args[1] begin
        @case "on"
        !config["isOff"] && @reply("悟理球已经粘在你的手上了，要再来一个吗")
        setJLD!(config, "isOff" => false)
        @reply("悟理球出现了！")

        @case "off"
        config["isOff"] && return nothing
        setJLD!(config, "isOff" => true)
        @reply("悟理球不知道哪里去了~")

        @case "exit"
        sendGroupMessage(text = "悟理球从这里消失了", chat_id = parse(Int, groupId))
        leaveGroup(chat_id = parse(Int, groupId))
        delete!(groupData, groupId)
        return nothing

        @case _
    end
    nothing
end

function diceSetConfig(msg, args)
    userId = msg.userId
    groupId = msg.groupId
    setting = args[1]
    groupConfig = getConfig!(groupId, userId)
    userConfig = getConfig!("private", userId)
    @switch setting begin
        @case "dnd"
        setJLD!(groupConfig, "gameMode" => :dnd, "defaultDice" => 20)
        @reply("已切换到DND模式，愿你在奇幻大陆上展开一场瑰丽的冒险！", false, false)

        @case "coc"
        setJLD!(groupConfig, "gameMode" => :coc, "defaultDice" => 100)
        @reply("已切换到COC模式，愿你在宇宙的恐怖真相面前坚定意志。", false, false)

        @case "detailed"
        setJLD!(groupConfig, "detailedDice" => true)
        @reply("详细骰点模式已开启", false, false)

        @case "simple"
        setJLD!(groupConfig, "detailedDice" => false)
        @reply("详细骰点模式已关闭", false, false)

        @case Re{r"rand=(default|jrrp|quantum)"}(capture)
        mode = Symbol(capture[1])
        setJLD!(userConfig, "randomMode" => mode)
        @switch mode begin
            @case :default
            @reply("已切换到默认随机模式，原汁原味的计算机随机数。")

            @case :jrrp
            @reply("已切换到人品随机模式，你的命运由今日人品决定！")

            @case :quantum
            @reply("已切换到量子随机模式，每次骰点一毛钱哦~")

            @case _
        end

        @case _
    end
    @reply("这是什么设置？悟理球不知道喵！")
end

function logSwitch(msg, args)
    op, str = args
    name = replace(str, r"^\s*|\s*$" => "")
    groupId = msg.groupId
    group = groupData[groupId]
    @switch op begin
        @case "on"
        isempty(name) && @reply("请提供一个日志名，不然悟理球不知道往哪里记啦")
        haskey(active_logs, groupId) && @reply("悟理球已经在记录日志了，再多要忙不过来了qwq")
        active_logs[groupId] = log_ref = Ref{GameLog}()
        if haskey(group, "logs/$name")
            log_ref[] = group["logs/$name"]
            @reply("（搬小板凳）继续记录 $name 的故事~", false, false)
        end
        log_ref[] = GameLog(name, groupId, now(), MessageLog[], Int[])
        @reply("（搬小板凳）开始记录 $name 的故事~", false, false)

        @case "new"
        isempty(name) && @reply("请提供一个日志名，不然悟理球不知道往哪里记啦")
        haskey(active_logs, groupId) && @reply("悟理球已经在记录日志了，再多要忙不过来了qwq")
        if haskey(group, "logs/$name")
            @reply("已经存在同名日志了，悟理球舍不得擅自把它删掉，换个名字吧", false, false)
        end
        active_logs[groupId] = Ref{GameLog}(GameLog(name, groupId, now(), MessageLog[], Int[]))
        @reply("（搬小板凳）开始记录 $name 的故事~", false, false)

        @case "off"
        !haskey(active_logs, groupId) && @reply("你要关什么？悟理球现在两手空空")
        log_ref = pop!(active_logs, groupId)
        name = log_ref[].name
        setJLD!(group, "logs/$name" => log_ref[])
        @reply("$name 的故事结束了，悟理球已经全都记下来了！", false, false)

        @case _
    end
    nothing
end

function logRemove(msg, args)
    name = replace(args[1], r"^\s*|\s*$" => "")
    groupId = msg.groupId
    group = groupData[groupId]
    (isempty(name) || !haskey(group, "logs/$name")) && @reply("找不到这个日志耶，确定不是日志名写错了吗？")
    delete!(group["logs"], name)
    @reply("$name 的故事在记忆里消散了", false, false)
end

function logList(msg, args)
    groupId = msg.groupId
    group = groupData[groupId]
    logging = haskey(active_logs, groupId) ? active_logs(groupId)[].name : ""
    reply_str = isempty(logging) ? "没有正在记录的日志~\n" : "正在记录：$logging\n"
    if !haskey(group, "logs") || isempty(group["logs"])
        reply_str *= "没有记录完成的日志~"
    else
        reply_str *= "记录完成的日志："
        for name ∈ keys(group["logs"])
            reply_str *= "\n$(name)"
        end
    end
    @reply(reply_str, false, false)
end

function logGet(msg, args)
    name = replace(args[1], r"^\s*|\s*$" => "")
    groupId = msg.groupId
    group = groupData[groupId]
    (isempty(name) || !haskey(group, "logs/$name")) && @reply("找不到这个日志耶，确定不是日志名写错了吗？")
    @async exportLog(group["logs/$name"])
    @reply("正在导出~请稍候~", false, false)
end

function invNew(msg, args) # 新建空白人物
    userId = msg.userId
    str = args[1]
    m = match(r"(.*)-(.*)", str)
    if m !== nothing
        name, skillstr = m.captures
        name = replace(name, r"^\s*|\s*$" => "")
    elseif match(r"[\-\d]", str) === nothing
        name = replace(str, r"^\s*|\s*$" => "")
        skillstr = ""
    else
        name = now() |> string
        skillstr = str
    end

    path = userId * '/' * name
    if haskey(userData, path)
        throw(DiceError("错误，已存在同名角色"))
    end

    inv = JLD2.Group(userData, path)
    inv["SaveTime"] = now()

    temp = Dict{String,Int}()
    skillstr = replace(skillstr, r"\s" => "")
    for m ∈ eachmatch(r"([^\d]*)(\d+)", skillstr)
        skill = m.captures[1] |> lowercase
        success = parse(Int, m.captures[2])
        if haskey(skillAlias, skill)
            skill = skillAlias[skill]
        end
        if haskey(defaultSkill, skill) && success == defaultSkill[skill]
            continue
        end
        temp[skill] = success
    end
    if haskey(inv, "敏捷") && !haskey(inv, "闪避")
        temp["闪避"] = inv["敏捷"] ÷ 2
    end
    if haskey(inv, "教育") && !haskey(inv, "母语")
        temp["母语"] = inv["教育"]
    end

    for (key, val) in temp
        inv[key] = val
    end
    if haskey(userData[userId], " select")
        delete!(userData[userId], " select")
    end
    userData[userId][" select"] = name
    @reply("你的角色已经刻在悟理球的 DNA 里了。")
end

function invRename(msg, args) # 支持将非当前选择人物卡重命名
    if !haskey(userData, "$(msg.userId)/ select")
        throw(DiceError("当前未选择人物卡，请先使用 `.pc 人物姓名` 选择人物卡或使用 `.new 姓名-属性列表` 创建人物卡"))
    end
    user = userData[msg.userId]
    name = user[" select"]
    new_name = replace(args[1], r"^\s*|\s*$" => "")
    if isempty(new_name)
        throw(DiceError("你说了什么吗，悟理球什么都没收到"))
    end
    if haskey(user, new_name)
        throw(DiceError("已经有叫这个名字的角色了哦，悟理球不忍心把他覆盖掉"))
    end
    new_inv = JLD2.Group(user, new_name)
    inv = user[name]
    for skill ∈ keys(inv)
        new_inv[skill] = inv[skill]
    end
    delete!(user, name)
    delete!(user, " select")
    user[" select"] = new_name
    @reply("从现在开始你就是 $new_name 啦！")
end

function invRemove(msg, args)
    name = replace(args[1], r"^\s*|\s*$" => "")
    if isempty(name)
        throw(DiceError("你说了什么吗，悟理球什么都没收到"))
    end
    if !haskey(userData, "$(msg.userId)/$name")
        throw(DiceError("不记得你有这张卡捏，检查一下是不是名字写错了吧"))
    end
    user = userData[msg.userId]
    delete!(user, name)
    if haskey(user, " select") && user[" select"] == name
        delete!(user, " select")
    end
    @reply("$name 已从这个世界上清除")
end

function invSelect(msg, args) # 与 invRemove 合并
    name = replace(args[1], r"^\s*|\s*$" => "")
    if isempty(name)
        throw(DiceError("你说了什么吗，悟理球什么都没收到"))
    end
    if !haskey(userData, "$(msg.userId)/$name")
        throw(DiceError("不记得你有这张卡捏，检查一下是不是名字写错了吧"))
    end
    user = userData[msg.userId]
    if haskey(user, " select") && user[" select"] == name
        @reply("你已经是 $name 了，不用再切换了")
    end
    setJLD!(user, " select" => name)
    @reply("你现在变成 $name 啦！")
end

function invLock(msg, args)
    @reply("Working in Progress...")
end

function invList(msg, args) # 支持按照编号删除
    userId = msg.userId
    select_str = "当前未选定任何角色"
    list_str = "角色卡列表为空"
    if haskey(userData, userId)
        if haskey(userData[userId], " select")
            name = userData[userId][" select"]
            select_str = "当前角色：$name"
        end
        list_temp = ""
        for name ∈ keys(userData[userId])
            if name[1] != ' '
                list_temp = list_temp * "\n" * name
            end
        end
        if !isempty(list_temp)
            list_str = "备选角色：" * list_temp
        end
    end
    @reply(select_str * "\n—————————————————\n" * list_str)
end

function skillShow(msg, args)
    userId = msg.userId
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 `.pc 人物姓名` 选择人物卡或使用 `.new 姓名-属性列表` 创建人物卡"))
    end
    str = args[1]
    word = match(r"^([^\s\d]+)", str)
    name = userData[userId][" select"]
    if word !== nothing
        skill = word.captures[1] |> lowercase
        if haskey(skillAlias, skill)
            skill = skillAlias[skill]
        end
        inv = userData[userId][name]
        if haskey(inv, skill)
            success = inv[skill]
        elseif haskey(defaultSkill, skill)
            success = defaultSkill[skill]
        else
            @reply("$name 好像没有 $(skill) 这个技能耶")
        end
        @reply("$name 的 $(skill)：$success")
    end
    @reply("显示所有技能值的功能还木有写出来...")
end

function skillRemove(msg, args)
    userId = msg.userId
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 `.pc 人物姓名` 选择人物卡或使用 `.new 姓名-属性列表` 创建人物卡"))
    end
    str = args[1]
    word = match(r"^([^\s\d]+)", str)
    name = userData[userId][" select"]
    if word !== nothing
        skill = word.captures[1] |> lowercase
        if haskey(skillAlias, skill)
            skill = skillAlias[skill]
        end
        inv = userData[userId][name]
        if haskey(defaultSkill, skill)
            inv[skill] = defaultSkill[skill]
            @reply("已经将 $name 的 $skill 技能恢复到初始值")
        elseif haskey(inv, skill)
            delete!(inv, skill)
            @reply("$name 忘记了 $skill 的用法")
        else
            @reply("$name 好像本来就不会 $skill")
        end
    end
    @reply("悟理球没法删掉没有名字的技能！")
end

function skillSet(msg, args)
    userId = msg.userId
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 `.pc 人物姓名` 选择人物卡或使用 `.new 姓名-属性列表` 创建人物卡"))
    end

    str = replace(args[2], r"\s" => "")
    if args[1] === nothing && length(str) >= 32
        @reply("悟理球的 .st 指令为修改当前人物卡的技能值，如果要新建人物卡请使用 .new，如果确认要一次性修改大量技能值请使用 .st force")
    end

    name = userData[userId][" select"]
    inv = userData[userId][name]

    text = "$name 的技能值变化："
    for m ∈ eachmatch(r"([^\d()+\-*]*)([+\-]?)([d\d()+\-*]+)", str)
        skill = m.captures[1] |> lowercase
        if haskey(skillAlias, skill)
            skill = skillAlias[skill]
        end
        text *= "\n" * skill * " "
        resultIR = rollDice(m.captures[3])[1]
        expr = resultIR.expr
        res = resultIR.total
        base = 0
        if haskey(inv, skill)
            base = inv[skill]
        elseif haskey(defaultSkill, skill)
            base = defaultSkill[skill]
        end
        flag = m.captures[2]
        if flag == "+"
            res = base + res
        elseif flag == "-"
            res = base - res
        end
        res = max(0, res)
        setJLD!(inv, skill => res)
        if isempty(flag)
            if match(r"[d\+\-]", expr) !== nothing
                text *= "$base => $expr = $res"
            else
                text *= "$base => $res"
            end
        else
            text *= "$base $flag$expr => $res"
        end
    end
    setJLD!(inv, "SaveTime" => now())
    @reply(text)
end

function initAdd(msg, args; overwrite = false) # 重写为读取完一次性添加
    if !haskey(group_init_list, msg.groupId)
        group_init_list[msg.groupId] = Ref{InitialList}(InitialList())
    end
    the_list = group_init_list[msg.groupId][]
    str = replace(args[1], r"[\s,，;、]+" => ",")
    str = replace(str, r"^,|,$" => "")
    buffer = IOBuffer()
    print(buffer, "添加了先攻条目")
    try
        for sub ∈ eachsplit(str, ",")
            isempty(sub) && (sub = "+0")
            for m ∈ eachmatch(r"([^\d()+\-*#]*)([d\d()+\-*]*)(#[d\d()+\-*]*)?", sub)
                isempty(m.match) && continue
                name, adjust_value, num_str = m.captures
                item_number = 0
                if isempty(name)
                    name = msg.userName
                else
                    query_item = query_initial_list(the_list, name)
                    if query_item !== nothing && query_item.name != name # Which means $name is like XXa
                        !overwrite && throw(DiceError("错误，先攻列表中已存在同名条目：$name"))
                        item_number = last(name) - 'a' + 1
                        name = query_item.name
                    end
                end
                isempty(adjust_value) && (adjust_value = "1d20+0")
                num = 1
                if num_str !== nothing && length(num_str) > 1
                    num_str[2] == '+' && (overwrite = false)
                    num = rollDice(@view(num_str[2:end]); defaultDice = 20, strict_calculate = true)[1].total
                    num <= 0 && continue
                end
                item_number > 0 && num > 1 && throw(DiceError("错误，修改单个条目的时候不允许添加次数！"))
                num > 10 && throw(DiceError("一次性添加的人太多了，骰子骰不过来了啦"))
                resultIRs = rollDice(adjust_value; defaultDice = 20, times = num)
                overwrite && delete_from_initial_list(the_list, name, item_number; preserve_multiple = false)
                for L ∈ resultIRs
                    entry_name = add_to_initial_list(the_list, name, L.total; number = item_number)
                    if 'd' ∈ L.expr
                        print(buffer, "\n$(entry_name)：$(L.expr)=$(L.total)")
                    else
                        print(buffer, "\n$(entry_name)：$(L.total)")
                    end
                end
            end
        end
        @reply(String(take!(buffer)))
    catch err
        reply_str = String(take!(buffer))
        '\n' ∈ reply_str && DiceReply(reply_str)(msg)
        rethrow()
    end
end
initSet(msg, args) = initAdd(msg, args; overwrite = true)

function initRemove(msg, args)
    !haskey(group_init_list, msg.groupId) && @reply("先攻列表空空如也~没有条目可以移除")
    the_list = group_init_list[msg.groupId][]
    str = replace(args[1], r"^\s*|\s*$" => "")
    isempty(str) && throw(DiceError("你说了什么吗，悟理球什么都没收到"))
    if last(str) == '*'
        name = @view str[1:prevind(str, end, 1)]
        if isempty(name)
            empty!(the_list.items)
            empty!(the_list.multiple.map)
            @reply("已清空先攻列表~悟理球准备好下一场战斗了！")
        end
        if the_list.multiple[name] > 0
            delete_from_initial_list(the_list, name, 0; preserve_multiple = false)
            @reply("再见了，所有的$(name)！")
        end
        throw(DiceError("先攻列表里真的有这个条目吗？悟理球没有找到"))
    end
    query_item = query_initial_list(the_list, str)
    query_item === nothing && throw(DiceError("先攻列表里真的有这个条目吗？悟理球没有找到"))
    if the_list.multiple[str] > 0
        query_item.number > 1 && @reply("存在多个条目的名字是 $(str)，请指明或使用 `.init rm $(str)*` 删除全部")
        delete_from_initial_list(the_list, str, 1)
        @reply("$str 已经不再属于这场战斗了")
    end
    if 'a' <= last(str) <= 'z'
        delete_from_initial_list(the_list, @view(str[1:prevind(str, end, 1)]), last(str) - 'a' + 1)
        @reply("$str 已经不再属于这场战斗了")
    end
    nothing
end

function initList(msg, args)
    !haskey(group_init_list, msg.groupId) && @reply("当前先攻列表为空，要开启一场新的战斗吗？")
    the_list = group_init_list[msg.groupId][]
    length(the_list) == 0 && @reply("当前先攻列表为空，要开启一场新的战斗吗？")
    buffer = IOBuffer()
    print(buffer, "当前先攻列表：")
    priority = typemax(Int64)
    for (it, val) ∈ the_list.items
        if priority > val
            priority = val
            print(buffer, "\n", val, "：")
        else
            print(buffer, "、")
        end
        name = it.name
        if the_list.multiple[name] > 1
            name *= '`' + it.number
        end
        print(buffer, name)
    end
    @reply(String(take!(buffer)), false, false)
end

function initClear(msg, args)
    if !haskey(group_init_list, msg.groupId)
        group_init_list[msg.groupId] = Ref{InitialList}(InitialList())
    end
    the_list = group_init_list[msg.groupId][]
    empty!(the_list.items)
    empty!(the_list.multiple.map)
    @reply("已清空先攻列表~悟理球准备好下一场战斗了！")
end

function randomTi(msg, args)
    fate = rand(1:10)
    res = """
    你的疯狂发作-即时症状：
    1d10 = $fate
    $(tiList[fate])\
    """
    @reply(res)
end

function randomLi(msg, args)
    fate = rand(1:10)
    res = """
    你的疯狂发作-总结症状：
    1d10 = $fate
    $(liList[fate])\
    """
    @reply(res)
end

function randomGas(msg, args)
    fate = (rand(1:6), rand(1:20))
    @reply(gasList[fate])
end

function jrrp(msg, args)
    userId = msg.userId
    seed = getJrrpSeed()
    rng = MersenneTwister(parse(UInt64, userId) ⊻ seed ⊻ 0x30113)
    rp = rand(rng, 1:100)
    @reply("今天你的手上粘了 $rp 个悟理球！")
end

function fuck2060(msg, args)
    @reply("玩你🐎透明字符呢，滚！", false, true)
end

const cmdList = [
    DiceCmd(initSet, r"^ri\s*([\s\S]*)", "设置先攻", Set([:group])),
    DiceCmd(roll, r"^r((?:[ach]|\d*b|\d*p)*)\s*(.*)", "骰点或检定", Set([:group, :private])),
    DiceCmd(charMake, r"^coc7?(.*)", "人物做成", Set([:group, :private])),
    DiceCmd(charMakeDnd, r"^dnd(.*)", "DnD人物做成", Set([:group, :private])),
    DiceCmd(botStart, r"^start$", "Hello, world!", Set([:private])),
    DiceCmd(botSwitch, r"^bot\s*(on|off|exit)", "bot开关", Set([:group, :off])),
    DiceCmd(botInfo, r"^bot$", "bot信息", Set([:group, :private])),
    DiceCmd(diceSetConfig, r"^set\s*(.*)", "Dice设置", Set([:group, :private])),
    DiceCmd(diceHelp, r"^help\s*(.*)", "获取帮助", Set([:group, :private])),
    DiceCmd(invNew, r"^(?:pc )?new\s*(.*)", "新建人物卡", Set([:group, :private])),
    DiceCmd(invRename, r"^pc (?:nn|mv|rename)\s*(.*)", "重命名人物卡", Set([:group, :private])),
    DiceCmd(invRename, r"^nn\s*(.*)", "重命名人物卡", Set([:group, :private])),
    DiceCmd(invRemove, r"^pc (?:del|rm|remove)\s*(.*)", "删除人物卡", Set([:group, :private])),
    DiceCmd(invLock, r"^pc (lock|unlock)", "锁定人物卡", Set([:group, :private])),
    DiceCmd(invList, r"^pc\s*(?:list)?$", "当前人物卡列表", Set([:group, :private])),
    DiceCmd(invSelect, r"^pc\s*(.+)", "切换人物卡", Set([:group, :private])),
    DiceCmd(skillShow, r"^st\s*show\s*(.*)", "查询技能值", Set([:group, :private])),
    DiceCmd(skillSet, r"^st( force)?\s*(.*)", "设定技能值", Set([:group, :private])),
    DiceCmd(skillRemove, r"^st\s*(?:del|rm|remove)\s*(.*)", "删除技能项", Set([:group, :private])),
    DiceCmd(sanCheck, r"^sc\s*(.*)", "理智检定", Set([:group, :private])),
    DiceCmd(skillEn, r"^en\s*(.*)", "技能成长", Set([:group, :private])),
    DiceCmd(randomTi, r"^ti", "随机疯狂发作-即时症状", Set([:group, :private])),
    DiceCmd(randomLi, r"^li", "随机疯狂发作-总结症状", Set([:group, :private])),
    DiceCmd(randomGas, r"^gas", "随机煤气灯特质", Set([:group, :private])),
    DiceCmd(logSwitch, r"^log\s*(new|on|off)\s*(.*)", "开启/关闭日志记录", Set([:group])),
    DiceCmd(logRemove, r"^log (?:del|rm|remove)\s*(.*)", "删除日志记录", Set([:group])),
    DiceCmd(logList, r"^log\s*(?:list)?$", "群聊日志列表", Set([:group])),
    DiceCmd(logGet, r"^log (?:get|export)\s*(.*)", "导出群聊日志", Set([:group])),
    DiceCmd(initAdd, r"^init\s*add([\s\S]*)", "设置先攻", Set([:group])),
    DiceCmd(initClear, r"^init\s*(?:clear)", "清空先攻列表", Set([:group])),
    DiceCmd(initRemove, r"^init\s*(?:del|rm|remove)\s*(.*)", "删除先攻列表元素", Set([:group])),
    DiceCmd(initList, r"^init\s*(?:list|show)?", "先攻列表", Set([:group])),
    DiceCmd(jrrp, r"^jrrp", "今日人品", Set([:group, :private])),
    DiceCmd(fuck2060, r"\u2060", "fuck\\u2060", Set([:group, :private])),
]