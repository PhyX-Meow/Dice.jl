include("utils.jl")

macro dice_str(str)
    :(rollDice($str)[2])
end

function getUserRng(userId)
    path = "$userId/ jrrpRng"
    if haskey(userData, path)
        if userData[path][1] == today()
            return userData[path][2]
        end
        delete!(userData, path)
    end
    rng = Random.MersenneTwister(getJrrpSeed() ⊻ parse(UInt64, userId))
    userData[path] = (today(), rng)
    return rng
end

function saveUserRng(userId)
    if getConfig("private", userId, "randomMode") == :jrrp
        setJLD!(userData, "$userId/ jrrpRng", (today(), deepcopy(getRngState())))
    end
    setRngState!()
end

function rollDice(str::AbstractString; defaultDice = 100, lead = false, detailed = false)
    m_comment = if match(r"\s", str) !== nothing
        match(r"\s(\S*?[^0-9d()+\-*/#\s][\s\S]*)", str)
    else
        match(r"([^0-9d()+\-*/#\s][\s\S]*)", str)
    end
    comment = isnothing(m_comment) ? "" : m_comment.captures[1]
    expr_str = replace(isnothing(m_comment) ? str : SubString(str, 1, m_comment.offset), r"\s" => "")
    m = match(r"([0-9d()+\-*/]*)(#\d+)?", expr_str)
    expr = m.captures[1]
    num_str = m.captures[2]
    num = 1
    if num_str !== nothing
        num = parse(Int, num_str[2:end])
    end
    num > 13 && throw(DiceError("骰子太多了，骰不过来了qwq"))

    if isempty(expr)
        expr = "1d$defaultDice"
    end
    if match(r"d\d*d", expr) !== nothing
        throw(DiceError("表达式有歧义，看看是不是有写出了XdYdZ样子的算式？"))
    end
    expr = replace(expr, r"(?<![\d)])d" => "1d")
    expr = replace(expr, r"d(?![\d(])" => "d$defaultDice")

    try
        if lead
            _expr_ = replace(expr, "d" => "↓", "/" => "÷") |> Meta.parse
            return (expr, eval(_expr_))
        end

        parsed_expr = replace(expr, "d" => "↑", "/" => "÷") |> Meta.parse
        _expr_ = expr_replace(parsed_expr, x -> x isa Int, x -> :(DiceIR($x)); skip = x -> (x.head == :call && x.args[1] == :↑))


        if num > 1 # No detail for multiple roll
            return ("$expr#$num", string([eval(_expr_).total for _ ∈ 1:num]))
        end

        result_IR = eval(_expr_)
        reply_str = result_IR.expr
        if detailed && 'd' ∈ result_IR.expr && match(r"^\[\d*\]$", result_IR.result) === nothing
            reply_str *= " = $(result_IR.result)"
        end
        return (reply_str, result_IR.total)
    catch err
        throw(DiceError("表达式格式错误，算不出来惹"))
        throw(err)
    end
end

function skillCheck(success::Int, rule::Symbol, bonus::Int)
    if success >= 1 << 16
        throw(DiceError("错误，成功率不合基本法"))
    end

    fate = rand(getRngState(), 1:100)
    res = "1d100 = $(fate)"

    if bonus != 0
        r = fate % 10
        bDice = rand(rng, 0:9, abs(bonus))
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
    res *= "/$(success)。"
    return res, check # 重构这里的代码
end

function roll(args; groupId = "", userId = "")
    defaultDice = getConfig(groupId, userId, "defaultDice")
    isDetailed = getConfig(groupId, userId, "detailedDice")
    randomMode = getConfig("private", userId, "randomMode")
    rng = @match randomMode begin
        :jrrp => getUserRng(userId)
        # :quantum => QuantumRNG()
        _ => Random.default_rng()
    end
    setRngState!(rng)

    ops, b, p, str = args
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
                res, check = skillCheck(success, rule, bonus)
                res *= rand(checkReply[check])
                randomMode == :jrrp && saveUserRng(userId)
                return DiceReply(res, hidden, true)
            end
        end
        word = match(r"^([^\s\d]+)", str)
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
        res, check = skillCheck(success, rule, bonus)
        res *= rand(checkReply[check])
        randomMode == :jrrp && saveUserRng(userId)
        return DiceReply(res, hidden, true)
    end

    expr, res = rollDice(str; defaultDice = defaultDice, detailed = isDetailed) # 重写这该死的骰点
    randomMode == :jrrp && saveUserRng(userId)
    return DiceReply("你骰出了 $expr = $res", hidden, true)
end

function sanCheck(args; groupId = "", userId = "") # To do: 恐惧症/躁狂症
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 .pc [人物姓名] 选择人物卡或使用 .new [姓名-<属性列表>] 创建人物卡"))
    end

    str = args[1]
    str = replace(str, r"\s" => "")
    m = match(r"([d\d\+\-\*]+)/([d\d\+\-\*]+)", str)
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
        return DiceReply("不用检定了，$name 已经永久疯狂了。")
    end

    sanMax = 99
    if haskey(inv, "克苏鲁神话")
        sanMax -= inv["克苏鲁神话"]
    end

    randomMode = getConfig("private", userId, "randomMode")
    rng = @match randomMode begin
        :jrrp => getUserRng(userId)
        # :quantum => QuantumRNG()
        _ => Random.default_rng()
    end
    setRngState!(rng)

    res, check = skillCheck(san, :book, 0)
    res = "$name 的理智检定：" * res
    @switch check begin
        @case :critical
        expr, loss = rollDice(succ)
        res *= "大成功！\n显然这点小事完全无法撼动你钢铁般的意志\n"

        @case:fumble
        expr, loss = rollDice(fail; lead = true)
        res *= "大失败！\n朝闻道，夕死可矣。\n"

        @case:failure
        expr, loss = rollDice(fail)
        res *= "失败\n得以一窥真实的你陷入了不可名状的恐惧，看来你的“觉悟”还不够呢\n"

        @case _
        expr, loss = rollDice(succ)
        res *= "成功\n真正的调查员无畏觅见真实！可是捱过了这次，还能捱过几次呢？\n"
    end
    san = max(0, san - loss)
    res *= "理智损失：$(expr) = $(loss)，当前剩余理智：$(san)/$(sanMax)"
    if san == 0
        res *= "\n调查员已陷入永久疯狂。"
    elseif loss >= 5
        res *= "\n单次理智损失超过 5 点，调查员已陷入临时性疯狂，使用 .ti/.li 可以获取随机疯狂发作症状"
    end

    delete!(inv, "SaveTime")
    inv["SaveTime"] = now()
    delete!(inv, "理智")
    inv["理智"] = san

    randomMode == :jrrp && saveUserRng(userId)
    return DiceReply(res)
end

function skillEn(args; groupId = "", userId = "")
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 .pc [人物姓名] 选择人物卡或使用 .new [姓名-<属性列表>] 创建人物卡"))
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
    fate = rand(1:100)
    if fate <= success
        return DiceReply("1d100 = $(fate)/$(success)\n失败了，什么事情都没有发生.jpg")
    end

    up = rand(1:10)
    delete!(inv, skill)
    inv[skill] = success + up
    delete!(inv, "SaveTime")
    inv["SaveTime"] = now()

    return DiceReply(
        """
        1d100 = $(fate)/$(success)
        成功！$name 的 $skill 成长：
        1d10 = $(up)，$success => $(success+up)\
        """,
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

function charMakeDnd(args; kw...)
    m = match(r"^\s*(\d+)", args[1])
    num = isnothing(m) ? 1 : parse(Int, m.captures[1])
    num > 10 && return DiceReply("单次人物做成最多 10 个哦，再多算不过来了")
    num <= 0 && return DiceReply("啊咧，你要捏几个人来着")

    res = "DND5e 人物做成："
    for _ in 1:num
        stats = [xdy(4, 6; take = 3) for _ ∈ 1:6]
        res = res * "\n" * string(stats) * "，总和：" * string(sum(stats))
    end
    return DiceReply(res, false, false)
end

function charMake(args; kw...)
    m = match(r"^\s*(\d+)", args[1])
    num = isnothing(m) ? 1 : parse(Int, m.captures[1])
    num > 10 && return DiceReply("单次人物做成最多 10 个哦，再多算不过来了")
    num <= 0 && return DiceReply("啊咧，你要捏几个人来着")

    res = [randChara() for _ ∈ 1:num]
    res[1] = "7 版人物做成：\n" * res[1]
    return DiceReply(res, false, false)
end

function botStart(args; kw...)
    return DiceReply("你现在也是手上粘着悟理球的 Friends 啦！", false, false)
end

function botInfo(args; kw...)
    return DiceReply(
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

function getConfig(groupId, userId) # This is read only
    config = getConfig!(groupId, userId)
    config_dict = Dict()
    for key ∈ keys(config)
        config_dict[key] = config[key]
    end
    return config_dict
end

function getConfig(groupId, userId, conf::AbstractString)
    return getConfig!(groupId, userId)[conf]
end

function getConfig!(groupId, userId) # This allows modification
    isempty(userId) && throw(DiceError("错误，未知的用户"))
    isempty(groupId) && throw(DiceError("错误，群号丢失"))

    dataSet = groupId == "private" ? userData : groupData
    path = groupId == "private" ? "$userId/ config" : groupId
    default = groupId == "private" ? defaultUserConfig : defaultGroupConfig

    if !haskey(dataSet, path)
        config = JLD2.Group(dataSet, path)
    else
        config = dataSet[path]
    end

    for (key, val) in default
        if !haskey(config, key)
            config[key] = val
        end
    end

    return config
end

function botSwitch(args; groupId = "", userId = "")
    config = getConfig!(groupId, userId)
    @switch args[1] begin
        @case "on"
        !config["isOff"] && return DiceReply("悟理球已经粘在你的手上了，要再来一个吗")
        setJLD!(config, "isOff" => false)
        return DiceReply("悟理球出现了！")

        @case "off"
        config["isOff"] && return noReply
        setJLD!(config, "isOff" => true)
        return DiceReply("悟理球不知道哪里去了~")

        @case "exit"
        sendMessage(text = "悟理球从这里消失了", chat_id = parse(Int, groupId))
        leaveChat(chat_id = parse(Int, groupId))
        delete!(groupData, groupId)
        return noReply

        @case _
    end
    return noReply
end

function diceSetConfig(args; groupId = "", userId = "")
    setting = args[1]
    group_config = getConfig!(groupId, userId)
    user_config = getConfig!("private", userId)
    @switch setting begin
        @case "dnd"
        setJLD!(group_config, "gameMode" => :dnd, "defaultDice" => 20)
        return DiceReply("已切换到DND模式，愿你在奇幻大陆上展开一场瑰丽的冒险！")

        @case "coc"
        setJLD!(group_config, "gameMode" => :coc, "defaultDice" => 100)
        return DiceReply("已切换到COC模式，愿你在宇宙的恐怖真相面前坚定意志。")

        @case "detailed"
        setJLD!(group_config, "detailedDice" => true)
        return DiceReply("详细骰点模式已开启")

        @case "simple"
        setJLD!(group_config, "detailedDice" => false)
        return DiceReply("详细骰点模式已关闭")

        @case Re{r"rand=(default|jrrp|quantum)"}(capture)
        mode = Symbol(capture[1])
        setJLD!(user_config, "randomMode" => mode)
        @switch mode begin
            @case :default
            return DiceReply("已切换到默认随机模式，原汁原味的计算机随机数。")

            @case :jrrp
            return DiceReply("已切换到人品随机模式，你的命运由今日人品决定！")

            @case :quantum
            return DiceReply("已切换到量子随机模式，每次骰点一毛钱哦~")

            @case _
        end

        @case _
    end
    return DiceReply("这是什么设置？悟理球不知道喵！")
end

function diceHelp(args; kw...)
    m = match(r"link", args[1])
    m !== nothing && return DiceReply(helpLinks, false, false)
    return DiceReply(helpText, false, false)
end

function invNew(args; groupId = "", userId = "") # 新建空白人物
    str = args[1]
    m = match(r"(.*)-(.*)", str)
    if m !== nothing
        name, skillstr = m.captures
        name = replace(name, r"^\s*|\s*$" => "")
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
    return DiceReply("你的角色已经刻在悟理球的 DNA 里了。")
end

function invRename(args; groupId = "", userId = "") # 支持将非当前选择人物卡重命名
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 .pc [人物姓名] 选择人物卡或使用 .new [姓名-<属性列表>] 创建人物卡"))
    end
    name = userData[userId][" select"]
    new_name = replace(args[1], r"^\s*|\s*$" => "")
    if isempty(new_name)
        throw(DiceError("你说了什么吗，我怎么什么都没收到"))
    end
    if haskey(userData[userId], new_name)
        throw(DiceError("错误，已存在同名角色"))
    end
    userData[userId][new_name] = userData[userId][name]
    delete!(userData[userId], name)
    delete!(userData[userId], " select")
    userData[userId][" select"] = new_name
    return DiceReply("从现在开始你就是 $new_name 啦！")
end

function invRemove(args; groupId = "", userId = "")
    name = replace(args[1], r"^\s*|\s*$" => "")
    if isempty(name)
        throw(DiceError("你说了什么吗，我怎么什么都没收到"))
    end
    if !(haskey(userData, userId) && haskey(userData[userId], name))
        throw(DiceError("我怎么不记得你有这张卡捏，检查一下是不是名字写错了吧"))
    end
    delete!(userData[userId], name)
    if haskey(userData[userId], " select") && userData[userId][" select"] == name
        delete!(userData[userId], " select")
    end
    return DiceReply("$name 已从这个世界上清除")
end

function invSelect(args; groupId = "", userId = "") # 与 invRemove 合并
    name = replace(args[1], r"^\s*|\s*$" => "")
    if isempty(name)
        throw(DiceError("你说了什么吗，我怎么什么都没收到"))
    end
    if !(haskey(userData, userId) && haskey(userData[userId], name))
        throw(DiceError("我怎么不记得你有这张卡捏，检查一下是不是名字写错了吧"))
    end
    if haskey(userData[userId], " select") && userData[userId][" select"] == name
        return DiceReply("你已经是 $name 了，不用再切换了")
    end
    delete!(userData[userId], " select")
    userData[userId][" select"] = name
    return DiceReply("你现在变成 $name 啦！")
end

function invLock(args; kw...)
    return DiceReply("WIP.")
end

function invList(args; groupId = "", userId = "") # 支持按照编号删除
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
                list_temp = list_temp * name * '\n'
            end
        end
        if !isempty(list_temp)
            list_str = "备选角色：\n" * list_temp
        end
    end
    return DiceReply(select_str * '\n' * "—————————————————\n" * list_str)
end

function skillShow(args; groupId = "", userId = "")
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 .pc [人物姓名] 选择人物卡或使用 .new [姓名-<属性列表>] 创建人物卡"))
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
            throw(DiceError("$name 好像没有 $(skill) 这个技能耶"))
        end
        return DiceReply("$name 的 $(skill)：$success")
    end
    return DiceReply("显示所有技能值的功能还木有写出来...")
end

function skillSet(args; groupId = "", userId = "") # Add .st rm
    if !haskey(userData, "$userId/ select")
        throw(DiceError("当前未选择人物卡，请先使用 .pc [人物姓名] 选择人物卡或使用 .new [姓名-<属性列表>] 创建人物卡"))
    end

    str = replace(args[2], r"\s" => "")
    if args[1] === nothing && length(str) >= 32
        return DiceReply("悟理球的 .st 指令为修改当前人物卡的技能值，如果要新建人物卡请使用 .new，如果确认要一次性修改大量技能值请使用 .st force")
    end

    name = userData[userId][" select"]
    inv = userData[userId][name]

    text = "$name 的技能值变化："
    for m ∈ eachmatch(r"([^\d\(\)\+\-\*]*)([\+\-]?)([d\d\(\)\+\-\*]+)", str)
        skill = m.captures[1] |> lowercase
        if haskey(skillAlias, skill)
            skill = skillAlias[skill]
        end
        text *= '\n' * skill * '\t'
        expr, res = rollDice(m.captures[3])
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
        delete!(inv, skill)
        inv[skill] = res
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

    delete!(inv, "SaveTime")
    inv["SaveTime"] = now()

    return DiceReply(text)
end

function randomTi(args; kw...)
    fate = rand(1:10)
    res = """
    你的疯狂发作-即时症状：
    1d10 = $fate
    $(tiList[fate])\
    """
    return DiceReply(res)
end

function randomLi(args; kw...)
    fate = rand(1:10)
    res = """
    你的疯狂发作-总结症状：
    1d10 = $fate
    $(liList[fate])\
    """
    return DiceReply(res)
end

function randomGas(args; kw...)
    fate = (rand(1:6), rand(1:20))
    return DiceReply(gasList[fate])
end

function getQuantum(length = 1, size = 4)
    api_key = get(ENV, "SUPER_SECRET_QUANTUM_API_KEY", "")
    headers = Dict("x-api-key" => api_key)
    resp = try
        HTTP.get("https://api.quantumnumbers.anu.edu.au?length=$length&type=hex16&size=4", headers, readtimeout = 1)
    catch err
        if err isa HTTP.Exceptions.TimeoutError
            throw(DiceError("量子超时:("))
        else
            throw(err)
        end
    end
    dataJSON = resp.body |> String |> JSON3.read
    if !dataJSON.success
        throw(DiceError("发生量子错误！"))
    end
    return parse.(UInt64, dataJSON.data, base = 16)
end

function getJrrpSeed()
    date = today() |> string
    haskey(jrrpCache, date) && return jrrpCache[date]
    jrrpCache[date] = seed = getQuantum(1, 4)[1]
    return seed
end

function jrrp(args; userId = "", kw...)
    seed = getJrrpSeed()
    rng = MersenneTwister(parse(UInt64, userId) ⊻ seed ⊻ 0x196883)
    rp = rand(rng, 1:100)
    return DiceReply("今天你的手上粘了 $rp 个悟理球！")
end

function fuck2060(args...)
    return DiceReply("玩你🐎透明字符呢，滚！", false, true)
end