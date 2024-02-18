function xdy(num::Integer, face::Integer; take::Integer = 0, rng = Random.default_rng())
    (num <= 0 || face <= 0) && throw(DiceError("悟理球无法骰不存在的骰子！"))
    num >= 1 << 16 && throw(DiceError("骰子太多了，骰不过来了qwq"))
    face >= 1 << 16 && throw(DiceError("你这骰子已经是个球球了，没法骰了啦！"))

    roll = rand(rng, 1:face, num)
    @match take begin
        GuardBy(>(0)) => sum(sort(roll, rev = true)[1:min(take, num)])
        GuardBy(<(0)) => sum(sort(roll)[1:min(-take, num)])
        _ => sum(roll)
    end
end

macro dice_str(str)
    :(rollDice($str)[2])
end

function rollDice(str::AbstractString; defaultDice = 100, lead = false)
    expr = replace(str, r"[^0-9d()+\-*/#]" => "")
    num = 1
    m_ = match(r"#.*$", expr)
    if m_ !== nothing
        m = match(r"#(\d*)$", expr)
        isnothing(m) && throw(DiceError("骰点次数指定(#数字)只能在表达式末尾哦"))
        expr = replace(expr, r"#.*$" => "")
        if !isempty(m.captures[1])
            num = parse(Int, m.captures[1])
        end
    end
    num <= 0 && throw(DiceError("悟理球无法骰不存在的骰子！"))
    num >= 42 && throw(DiceError("骰子太多了，骰不过来了qwq"))

    if isempty(expr)
        expr = "1d$defaultDice"
    end
    if match(r"d\d*d", expr) !== nothing
        throw(DiceError("表达式格式错误，算不出来惹"))
    end
    expr = replace(expr, r"(?<!\d)d" => "1d")
    expr = replace(expr, r"d(?!\d)" => "d$defaultDice")
    if !lead
        expr_ = replace(expr, r"(\d+)d(\d+)" => s"xdy(\1,\2)", "/" => "÷")
    else
        expr_ = replace(expr, r"(\d+)d(\d+)" => s"\1*\2", "/" => "÷")
    end

    expr__ = try
        Meta.parse(expr_)
    catch _
        throw(DiceError("表达式格式错误，算不出来惹"))
    end

    if num > 1
        return ("$expr#$num", string([eval(expr__) for _ ∈ 1:num]))
    end
    return (expr, eval(expr__))
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
    res *= "/$(success)。"
    return res, check # 重构这里的代码
end

function roll(args; groupId = "", userId = "")
    config = groupId == "private" ? getUserConfig(userId) : getGroupConfig(groupId)

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
                res *= rand(diceDefault.customReply[check])
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
        res *= rand(diceDefault.customReply[check]) # 重构此处代码
        return DiceReply(res, hidden, true)
    end

    expr, res = rollDice(str; defaultDice = config.defaultDice)
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

    res, check = skillCheck(san, :book, 0)
    res = "$name 的理智检定：" * res
    if check == :critical
        expr, loss = rollDice(succ)
        res *= "大成功！\n显然这点小事完全无法撼动你钢铁般的意志\n"
    elseif check == :fumble
        expr, loss = rollDice(fail; lead = true)
        res *= "大失败！\n朝闻道，夕死可矣。\n"
    elseif check == :failure
        expr, loss = rollDice(fail)
        res *= "失败\n得以一窥真实的你陷入了不可名状的恐惧，看来你的“觉悟”还不够呢\n"
    else
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

function randCharaDnd()
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

function getGroupConfig(groupId)
    isempty(groupId) && throw(DiceError("错误，群号丢失"))
    !haskey(groupData, groupId) && (groupData[groupId] = groupDefault)
    return groupData[groupId]
end

function getUserConfig(userId)
    isempty(userId) && throw(DiceError("错误，未知用户"))
    path = "$userId/ config"
    !haskey(userData, path) && (userData[path] = groupDefault)
    return userData[path]
end

function botSwitch(args; groupId = "", kw...)
    config = getGroupConfig(groupId)
    @switch args[1] begin
        @case "on"
        if config.isOff
            config.isOff = false
            delete!(groupData, groupId)
            groupData[groupId] = config
            return DiceReply("悟理球出现了！")
        end
        return DiceReply("悟理球已经粘在你的手上了，要再来一个吗")

        @case "off"
        config.isOff && return noReply
        config.isOff = true
        delete!(groupData, groupId)
        groupData[groupId] = config
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

function diceConfig(args; groupId = "", kw...)
    setting = args[1]
    config = getGroupConfig(groupId)
    @switch setting begin
        @case "dnd"
        config.mode = :dnd
        config.defaultDice = 20
        delete!(groupData, groupId)
        groupData[groupId] = config
        return DiceReply("已切换到DND模式，愿你在奇幻大陆上展开一场瑰丽的冒险！")

        @case "coc"
        config.mode = :coc
        config.defaultDice = 100
        delete!(groupData, groupId)
        groupData[groupId] = config
        return DiceReply("已切换到COC模式，愿你在宇宙的恐怖真相面前坚定意志。")

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
    newname = replace(args[1], r"^\s*|\s*$" => "")
    if isempty(newname)
        throw(DiceError("你说了什么吗，我怎么什么都没收到"))
    end
    if haskey(userData[userId], newname)
        throw(DiceError("错误，已存在同名角色"))
    end
    userData[userId][newname] = userData[userId][name]
    delete!(userData[userId], name)
    delete!(userData[userId], " select")
    userData[userId][" select"] = newname
    return DiceReply("从现在开始你就是 $newname 啦！")
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

function getJrrpSeed()
    date = today() |> string
    haskey(jrrpCache, date) && return jrrpCache[date]

    headers = Dict("x-api-key" => "6qrS9dAjZg5zwmi386Ppm7CkAQuMllgP1bpzPb3J")
    resp = try
        HTTP.get("https://api.quantumnumbers.anu.edu.au?length=1&type=hex16&size=4", headers, readtimeout = 1)
    catch err
        if err isa HTTP.Exceptions.TimeoutError
            throw(DiceError("哦不，今日人品获取超时了:("))
        else
            throw(err)
        end
    end
    dataJSON = resp.body |> String |> JSON3.read
    if !dataJSON.success
        throw(DiceError("今日人品获取失败"))
    end
    jrrpCache[date] = seed = parse(UInt64, dataJSON.data[1], base = 16)
    return seed
end

function jrrp(args; userId = "", kw...)
    seed = getJrrpSeed()
    rng = MersenneTwister(parse(UInt64, userId) ⊻ seed)
    rp = rand(rng, 1:100)
    return DiceReply("今天你的手上粘了 $rp 个悟理球！")
end

function fuck2060(args...)
    return DiceReply("玩你🐎透明字符呢，滚！", false, true)
end