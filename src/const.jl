const diceVersion = v"0.2.0"

struct DiceError <: Exception
    text::String
end

struct DiceCmd
    func::Symbol
    reg::Regex
    desp::String
    options::Set{Symbol}
end

struct DiceReply
    text::Array{AbstractString}
    hidden::Bool
    ref::Bool
end
DiceReply(str::AbstractString, hidden::Bool, ref::Bool) = DiceReply([str], hidden, ref)
DiceReply(str::AbstractString) = DiceReply(str, false, true)
const noReply = DiceReply(AbstractString[], false, false)

struct DiceConfig
    customReply::Dict{Symbol,Array{String}}
end

mutable struct GroupConfig
    rcRule::Symbol
    isOff::Bool
    team::Array{Int}
end

const groupDefault = GroupConfig(:book, false, Int[])

const diceDefault = DiceConfig(
    Dict(
        :critical => [
            "锵锵锵！大成功出现了！",
            "出现了！是大成功！",
            "大成功！KP快给奖励(盯)",
            "是大成功诶！快感谢我~"
        ],
        :extreme => [
            "极难成功，干得漂亮~",
            "是极难成功，すごいい！",
            "极难成功！如果是战斗轮就满伤了诶",
            "极难成功！虽然不是大成功，不过极难成功已经很厉害了"
        ],
        :hard => [
            "是困难成功诶",
            "困难成功，运气不错呢~",
            "哎嘿是困难成功",
            "咣当，咣当，困难成功",
            "是困难成功，sasuga"
        ],
        :regular => [
            "简单的成功了。",
            "成功了！好耶————",
            "收下吧！这就是我最后的成功了！(并不)",
            "当我说出“成功”两个字的时候，我的行动早已完成了！",
        ],
        :failure => [
            "失败了，惨惨。",
            "失败了唔，心疼你一秒",
            "好可惜，失败了唔",
            "失败，想要成功就给我打钱(无情)",
            "失败，庆幸不是大失败吧~啊哈哈哈",
            "失败了，我跟你们讲，其实本来是大失败的，我和KP做了秘密交易才改成了普通失败",
        ],
        :fumble => [
            "你以为能骰出成功？其实是大失败哒！",
            "大失败！我悟理球最喜欢做的事情之一，就是对自以为可以骰出成功的 pc 们 say “NO！”",
            "大失败！不过没关系，人类的赞歌就是勇气的赞歌！要相信自己！",
            "大失败！圣人云：骰出大失败才是跑团的乐趣。",
            "大失败！也许这就是命运。",
            "大失败！正如同宇宙的真实一样，悟理球是残酷且无理性的。"
        ]
    )
)

mutable struct Investigator
    savetime::DateTime
    skills::Dict{String,Int}
end

const defaultSkill = Dict( # 单独处理闪避和母语
    "会计" => 5,
    "表演" => 5,
    "动物驯养" => 5,
    "人类学" => 1,
    "估价" => 5,
    "考古学" => 1,
    "炮术" => 1,
    "天文学" => 1,
    "斧" => 15,
    "生物学" => 1,
    "植物学" => 1,
    "弓" => 15,
    "斗殴" => 25,
    "链锯" => 10,
    "取悦" => 15,
    "化学" => 1,
    "攀爬" => 20,
    "计算机使用" => 5,
    "信用评级" => 0,
    "密码学" => 1,
    "克苏鲁神话" => 0,
    "爆破" => 1,
    "乔装" => 5,
    "潜水" => 1,
    "闪避" => 1,
    "汽车驾驶" => 20,
    "电气维修" => 10,
    "电子学" => 1,
    "工程学" => 1,
    "话术" => 5,
    "美术" => 5,
    "急救" => 30,
    "连枷" => 10,
    "火焰喷射器" => 10,
    "司法科学" => 1,
    "伪造文书" => 5,
    "绞索" => 15,
    "地质学" => 1,
    "手枪" => 20,
    "重武器" => 10,
    "历史" => 5,
    "催眠" => 1,
    "恐吓" => 15,
    "跳跃" => 20,
    "母语" => 1,
    "法律" => 5,
    "图书馆使用" => 20,
    "聆听" => 20,
    "锁匠" => 1,
    "机枪" => 10,
    "数学" => 10,
    "机械维修" => 10,
    "医学" => 1,
    "气象学" => 1,
    "博物学" => 10,
    "导航" => 10,
    "神秘学" => 5,
    "操作重型机械" => 1,
    "说服" => 1,
    "药学" => 1,
    "摄影" => 5,
    "物理学" => 1,
    "精神分析" => 1,
    "心理学" => 10,
    "读唇" => 1,
    "骑术" => 5,
    "步枪/霰弹枪" => 25,
    "妙手" => 10,
    "矛" => 20,
    "侦查" => 25,
    "潜行" => 20,
    "冲锋枪" => 15,
    "生存" => 10,
    "刀剑" => 20,
    "游泳" => 20,
    "投掷" => 20,
    "追踪" => 10,
    "鞭" => 5,
    "动物学" => 1
)

const skillAlias = Dict(
    "str" => "力量",
    "con" => "体质",
    "siz" => "体型",
    "dex" => "敏捷",
    "app" => "外貌", "外表" => "外貌",
    "int" => "智力", "灵感" => "智力",
    "pow" => "意志",
    "edu" => "教育", "知识" => "教育",
    "luc" => "幸运", "运气" => "幸运",
    "san" => "理智", "san值" => "理智", "理智值" => "理智",
    "计算机" => "计算机使用", "电脑" => "计算机使用",
    "魅惑" => "取悦",
    "信用" => "信用评级", "信誉" => "信用评级",
    "cm" => "克苏鲁神话", "克苏鲁" => "克苏鲁神话",
    "汽车" => "汽车驾驶", "驾驶" => "汽车驾驶",
    "马术" => "骑术",
    "步枪" => "步枪/霰弹枪", "霰弹枪" => "步枪/霰弹枪", "霰弹" => "步枪/霰弹枪", "步霰" => "步枪/霰弹枪",
    "图书馆" => "图书馆使用",
    "自然学" => "博物学",
    "领航" => "导航",
    "重型操作" => "操作重型机械", "重型机械" => "操作重型机械", "操作重机" => "操作重型机械",
    "侦察" => "侦查",
    "剑" => "刀剑",
    "hp" => "体力",
    "mp" => "魔法"
)

const superAdminList = [0xc45c1b20b131d1c8]
const adminList = [0xc45c1b20b131d1c8, 0x192e269af0e0ce03]
const cmdList = [
    DiceCmd(:roll, r"^r(?:([ach])|(\d?)b|(\d?)p)*\s*(.*)", "骰点或检定", Set([:group, :private])),
    DiceCmd(:charMake, r"^coc7?(.*)", "人物做成", Set([:group, :private])),
    DiceCmd(:botStart, r"^start$", "Hello, world!", Set([:private])),
    DiceCmd(:botSwitch, r"^bot (on|off|exit)", "bot开关", Set([:group, :off])),
    DiceCmd(:botInfo, r"^bot$", "bot信息", Set([:group, :private])),
    DiceCmd(:diceConfig, r"^conf(.*)", "Dice设置", Set([:group, :private])),
    DiceCmd(:diceHelp, r"^help\s*(.*)", "获取帮助", Set([:group, :private])),
    DiceCmd(:invNew, r"^(?:pc )?new\s*(.*)", "新建人物卡", Set([:group, :private])),
    DiceCmd(:invRename, r"^pc (?:nn|mv|rename)\s*(.*)", "重命名人物卡", Set([:group, :private])),
    DiceCmd(:invRename, r"^nn\s*(.*)", "重命名人物卡", Set([:group, :private])),
    DiceCmd(:invRemove, r"^pc (?:del|rm|remove)\s*(.*)", "删除人物卡", Set([:group, :private])),
    DiceCmd(:invLock, r"^pc (lock|unlock)", "锁定人物卡", Set([:group, :private])),
    DiceCmd(:invList, r"^pc(?: list)?\s*$", "当前人物卡列表", Set([:group, :private])),
    DiceCmd(:invSelect, r"^pc\s*(.+)", "切换人物卡", Set([:group, :private])),
    DiceCmd(:skillShow, r"^st show\s*(.*)", "查询技能值", Set([:group, :private])),
    DiceCmd(:skillSet, r"^st( force)\s*(.*)", "设定技能值", Set([:group, :private])),
    DiceCmd(:sanCheck, r"^sc\s*([\dd\+\-\*]+)/([\dd\+\-\*]+)", "理智检定", Set([:group, :private])),
    DiceCmd(:jrrp, r"^jrrp", "今日人品", Set([:group, :private])),
    DiceCmd(:fuck2060, r"\u2060", "fuck\\u2060", Set([:group, :private]))
]

const helpText = """
    Dice Julian, made by 悟理(@phyxmeow).
    Version $diceVersion
    ———————————————————————————————
    目前可用的指令列表：
    .help
    .bot [on/off/exit]
    .r[c/a][b/p][h]
    .r XdY
    .coc [数量]
    .jrrp
    """
const helpLinks = """
    项目主页: https://github.com/PhyX-Meow/Dice.jl
    纯美苹果园: http://www.goddessfantasy.net/bbs/index.php
    魔都: https://cnmods.net/#/homePage
    骰声回响: https://dicecho.com/
    空白人物卡: https://1drv.ms/x/s!AnsQDRnK8xdggag-W_KjQsuJNU1Usw?e=H9MSPI
    守密人规则书: https://1drv.ms/b/s!AnsQDRnK8xdggZUiWCC3EsnUGpziEg?e=5mxIx5
    """

const kwList = Dict(
    "悟理球" => ["悟理球在！", "需要骰子吗！"],
    ".dismiss" => ["悟理球不仅没有走，反而粘到了你的手上。"],
    "JOJO" => [
        "Wryyyyyyyyyyyyyyy!!!!!!!",
        "ko no dio da!",
        "ROAD ROOOOOOLLER DAAA!!!",
        "平角裤平角裤",
        "人行道上不是很宽敞吗，开车",
        "你会记住你你吃过多少面包吗",
        "我真是high到不行了！",
        "我不做人了！JOJO！",
        "中计了吧！这就是我的逃跑路线！",
        "砸！瓦鲁多！",
        "老东西，你的替身最没用了！",
        "你竟敢…(呜呜呜)竟敢…(呜呜呜)竟敢…(呜呜呜)竟敢…打我！",
        "木大木大木大木大木大木大木大！",
        "JoJo，人的能力是有极限的，我从短暂的人生当中学到一件事...越是玩弄计谋,就越会发现人类的能力是有极限的....除非超越人类。",
        "不愧是DIO！我们不敢做的事，他毫不在乎地做了！真是佩服，真是我们的偶像！",
        "我们乔斯达家族世世代代都是绅士！",
        "我要打！继续打！把你打到哭出来！",
        "我的青春是和迪奥一起的青春！从现在开始我要和那青春做个了结！",
        "我从地狱回来了！迪奥！",
        "←To Be Continued...|\\|/",
        "人与人之间的相会，或许真的是命运也说不定。",
        "人类的赞歌就是勇气的赞歌！！ 人类的伟大就是勇气的伟大！！",
        "姐姐，「明天」就是现在！",
        "你的下一句话是：",
        "汤姆逊波纹疾走！",
        "泥给路哒哟——",
        "不愧是德意志军，竟然一下子就识破了我的伪装",
        "OHHHH!!!NOOOOOOO!!!!",
        "我最讨厌的字眼就是“努力”和“加油”了！",
        "西——————撒——————",
        "OH！MY！GOD！",
        "JOJO！这就是我最后的波纹了！收下吧！",
        "德意志的科学技术世界第一！！！",
        "接下来，我们看看这门缝里能看到什么（滑稽）",
        "秘技，神砂岚！",
        "我不后悔，因为能见到你的成长，……我流浪了一万年，可能是为了遇见你……",
        "啊 ~ 魔 理 沙 ~ ！",
        "WIN~WIN~WIN~WIN~",
        "卡兹，停止了思考。",
        "yareyaredaze",
        "欧拉欧拉欧拉欧拉欧拉欧拉欧拉欧拉欧拉欧拉欧拉欧拉欧拉欧拉",
        "Star Platinum，THE WORLD！",
        "接下来要干掉你连一秒都不需要！",
        "你失败的原因只有一个，DIO，一个很简单的原因，那就是你把我给惹怒了。",
        "即便是这样的我，也能分辨出那些令人作呕的邪恶！所谓邪恶，就是你这样为了自己而利用弱者并践踏他们的家伙！",
        "YES！YES！YES！",
        "rerorerorerorero rerorerorerorerorero",
        "Yes！I Am！",
        "波鲁那列夫！伊奇！危险！",
        "接招吧DIO！半径二十米，绿宝石水花！",
        "Magicians Red！",
        "Silver Chariots！",
        "我才发现...我是那么的喜欢它...为什么我总是失去了才懂得珍惜...",
        "吾名为「简·皮耶尔·波鲁那雷夫」，为告慰吾妹雪莉在天之灵，J·凯尔，我一定要把你推下罪恶的深渊！",
        "真是够了……我实在不能眼睁睁地看着一个爱狗的小孩……被它给杀了啊！",
        "给我多活几年啊...乔斯达先生！",
        "你说我的发型怎么了？！",
        "但是我拒绝！我岸边露伴最喜欢做的事情之一，就是对那些自以为是的家伙say“NO”来拒绝他们！",
        "承太郎先生！快用你无敌的白金之星想想办法啊！",
        "S.H.I.T.",
        "Killer Queen，第三炸弹，败者食尘！",
        "哟，安杰罗~",
        "dorararararara——",
        "好清爽的感觉！就像是在新年的早上换上新内裤一样的感觉啊！",
        "我吉良吉影只想要过平静的生活",
        "我名叫吉良吉影，33岁。住在杜王町东北部的别墅区一带，未婚。我在龟友连锁店服务。每天都要加班到晚上8点才能回家。我不抽烟，酒仅止于浅尝。晚上11点睡，每天要睡足8个小时。睡前，我一定喝一杯温牛奶，然后做20分钟的柔软操，上了床，马上熟睡。一觉到天亮，早上起来就像婴儿一样不带任何疲劳和压力迎接第二天。医生乔可拉特都说我没有任何异常。",
        "Heaven's Door！",
        "Echoes Act3！3 Freeze",
        "当我第一次看到…「蒙娜丽莎」交叉放在膝盖的「手」…嘿嘿……怎么说呢，说起来有点下流…我竟然…boki了…",
        "ARRIVEDERCI！",
        "阿里阿里阿里阿里阿里阿里阿里阿里",
        "之后的事就交给你了…乔鲁诺，替我向大家问好啊。",
        "（舔）这味道！是说谎的味道！",
        "Volare Via.",
        "Aero Smith！",
        "@@@",
        "我乔鲁诺·乔巴拿有一个梦想，那就是成为Gang Star！",
        "你应该有所觉悟吧！想要解决人，就可能反过来被解决。你应该常常有这种「危险的觉悟」才对",
        "你不要靠近我啊啊啊啊啊啊啊！！！",
        "我...我啊...等我回到故乡之后...我要去上学...我要把小学念完，被其他人笑我笨也没关系...我还要大口品尝故乡那种用栎木柴现烤热腾腾的玛格丽特披萨！上面还要加牛肚菇！",
        "A——NI——KI————",
        "当我们心中浮现出“宰了他们”这句话时！我们的行动早就已经完成了！",
        "普罗休特大哥，我知道了！我并非透过「言语」，而是透过「内心」，理解到大哥的觉悟了！",
        "哟~西，哟西哟西哟西哟西哟西哟西哟西哟西哟西哟西",
        "为什么不是3也不是5，偏偏是4啊",
        "不准给我踏上阶梯半步！我在上面！而你在下面！"
    ]
)