const diceVersion = v"0.3.0"

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
DiceReply(str::AbstractString) = DiceReply([str], false, true)
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
            "是大成功诶！快感谢我~",
        ],
        :extreme => [
            "极难成功，干得漂亮~",
            "是极难成功，すごいい！",
            "极难成功！如果是战斗轮就满伤了诶",
            "极难成功！虽然不是大成功，不过极难成功已经很厉害了",
        ],
        :hard => [
            "是困难成功诶",
            "困难成功，运气不错呢~",
            "哎嘿是困难成功",
            "咣当，咣当，困难成功",
            "是困难成功，sasuga",
        ],
        :regular => [
            "简单的成功了。",
            "成功了！好耶——",
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
            "大失败！正如同宇宙的真实一样，悟理球是残酷且无理性的。",
        ],
    ),
)

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
    "动物学" => 1,
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
    "mp" => "魔法",
    "修改日期" => "SaveTime", "日期" => "SaveTime",
)

const charaTemplate = quote
    """
    力量:$str 敏捷:$dex 意志:$pow
    体质:$con 外貌:$app 教育:$edu
    体型:$siz 智力:$int 幸运:$luc
    HP:$hp MP:$mp DB:$db MOV:$mov
    总和:$total/$luc_total\
    """
end

const tiList = Dict(
    1 => "失忆：调查员会发现自己只记得最后身处的安全地点，却没有任何来到这里的记忆。例如，调查员前一刻还在家中吃着早饭，下一刻就已经直面着不知名的怪物。这将会持续 1D10 轮。",
    2 => "假性残疾：调查员陷入了心理性的失明，失聪或躯体缺失感中，持续 1D10 轮。",
    3 => "暴力倾向：调查员陷入了六亲不认的暴力行为中，对周围的敌人与友方进行着无差别的攻击，持续 1D10 轮。",
    4 => "偏执：调查员陷入了严重的偏执妄想之中，持续 1D10 轮。所有人都想要伤害他们；没有人可以信任；他们正在被监视；有人背叛了他们；他们见到的都是诡计。",
    5 => "人际依赖：守密人适当参考调查员的背景中重要之人的条目，调查员因为一些原因而将他人误认为了他重要的人，考虑他们的关系性质，调查员会据此行动，持续 1D10 轮",
    6 => "昏厥：调查员当场昏倒，并需要 1D10 轮才能苏醒。",
    7 => "逃避行为：调查员会用任何的手段试图逃离现在所处的位置，即使这意味着开走唯一一辆交通工具并将其它人抛诸脑后，调查员会试图逃离 1D10 轮。",
    8 => "竭嘶底里：调查员表现出大笑，哭泣，嘶吼，害怕等的极端情绪表现，持续 1D10 轮。",
    9 => "恐惧：调查员骰一个 D100 或者由守秘人选择，来从恐惧症状表中选择一个恐惧源，就算这一恐惧源并不存在，调查员也会在接下来的 1D10 轮内想象它存在。",
    10 => "躁狂：调查员骰一个 D100 或者由守秘人选择，来从躁狂症状表中选择一个躁狂的诱因，在接下来的 1D10 轮内，调查员会渴望沉溺于他新的躁狂症中",
)

const liList = Dict(
    1 => "失忆：回过神来，调查员们发现自己身处一个陌生的地方，并忘记了自己是谁。记忆会随时间缓缓恢复。",
    2 => "被窃：调查员在 1D10 小时后恢复清醒，发觉自己被盗，身体毫发无损。如果调查员携带着宝贵之物（见调查员背景），做幸运检定来决定其是否被盗。其他所有贵重品无需检定自动消失。",
    3 => "遍体鳞伤：调查员在 1D10 小时后恢复清醒，发现自己身上满是拳痕和瘀伤。生命值减少到疯狂前的一半，但这不会造成重伤。调查员没有被窃。这种伤害从何而来由守秘人决定。",
    4 => "暴力倾向：调查员陷入强烈的暴力与破坏欲之中。当调查员回过神来时，他们做过什么可能很明显，可能被他们记住，也可能并不。调查员对谁或何物施以暴力，他们是杀人还是仅仅造成了伤害，由守秘人决定。",
    5 => "极端信念：查看调查员背景中的思想信念，调查员会采取极端和疯狂的表现手段展示他们的思想信念之一。比如一个信教者可能之后被发现正在地铁上高声布道。",
    6 => "重要之人：考虑调查员背景中的重要之人，及其重要的原因。在 1D10 小时或更久的时间中，调查员将不顾一切地接近那个人，并按照他们之间的关系做出行动。",
    7 => "被收容：调查员在精神病院病房或警察局牢房中回过神来，他们可能会慢慢回想起导致自己被关在这里的事情。",
    8 => "逃避行为：调查员恢复清醒时发现自己在很远的地方，也许迷失在荒郊野岭，或是在驶向远方的列车或长途汽车上。",
    9 => "恐惧：调查员患上一个新的恐惧症。在表Ⅸ：恐惧症状表上骰 1D100 来决定症状，或由守秘人选择一个。调查员在 1D10 小时后回过神来，并开始为避开恐惧源而采取任何措施。",
    10 => "躁狂：调查员患上一个新的躁狂症。在表Ⅹ：躁狂症状表上骰 1D100 来决定症状，或由守秘人选择一个。调查员会在 1D10 小时后恢复理智。在这次疯狂发作中，调查员将完全沉浸于其新的躁狂症状。这对旁人来说是否明显取决于守秘人和玩家。",
)

const gasList = Dict(
    (1, 1) => "任意选择一个有(D)记号的特征。",
    (1, 2) => "高龄(D)：年龄追加[(1D3+1)*10]岁，参照6版标准规则，超过30岁后开始获得EDU加值，40岁以后开始对于身体属性造成减值。",
    (1, 3) => "优雅的岁数： 40岁开始对身体能力造成减值的规则改为从50岁开始。",
    (1, 4) => "白化病患者(D)：STR，CON，SIZ，DEX，POW，APP中的任意一项减少3点。在明亮阳光下时[侦察]技能值减少[1D4-1]点，长时间受到光照的话会受到1点以上的HP伤害。白化病人在人群中很显眼并可能被他人用有色目光看待。",
    (1, 5) => "酒精中毒(D)：CON-1。STR，DEX，POW，APP中任意一项减少1点。为了避免陷入酩酊大醉需要通过一个SAN CHECK。陷入疯狂的情况下，调查员可能会寻求酒精来逃避现实。",
    (1, 6) => "警戒：不易被惊吓到。潜伏时一直都保持着能够随时[侦察]或者[聆听]的状态。",
    (1, 7) => "同盟者：投掷一个D100来决定同盟的力量/数量和出现的频率(D100的出点越大可能能够获得越有利的同盟)。用途不限。",
    (1, 8) => "双手灵活：调查员可以灵活的使用他的任意一只手而不会受到非惯用手的惩罚。",
    (1, 9) => "讨厌动物(D)：技能和动物有关时技能成功率减少[1D6*5]点。",
    (1, 10) => "艺术天才：音乐，写作之类的艺术技能增加[INT*5]%。",
    (1, 11) => "运动：运动系技能获得加值=选择一个技能+30%，或者选择两个技能各+20%，或者选择三个技能各+10%。",
    (1, 12) => "夜视强化：日落西山后视觉相关惩罚只有常人的一半。",
    (1, 13) => "累赘(D)：调查员出生于世家但是却没能达到家人的期待，或者不服管教。对于交涉系技能可能会造成影响而减少[1D3*10]%。",
    (1, 14) => "领导者资质：POW+1D2，交涉系技能+[INT*5]%。",
    (1, 15) => "打斗者：[拳击]或者[擒拿]+[1D4*5]%，每回合可以进行两次[拳击]或者[擒拿]，攻击成功时+1点伤害。",
    (1, 16) => "笨拙(D)：大失败的几率变成通常的2倍，并且大失败时可能会招致灾难。",
    (1, 17) => "收藏家：调查员有收集硬币，书，昆虫，艺术作品，宝石，古董之类的爱好。",
    (1, 18) => "身体障碍(D)：失去了身体的一部分。投掷一个D6。1~2=脚，3~4=手，5=头部(投掷D6，1~3=眼睛，4~6=耳朵)，6=玩家自己选择。失去脚的话DEX-3，STR或者CON-1，MOVE只有常人的一半，所有运动系技能-25%。失去手腕的话STR-1，DEX-2.所有的操作系技能-15%，使用武器会受到限制。失去眼睛的话[侦察]和火器技能等全部-35%，另外投掷一个[幸运]，失败的话APP-1D2。失去耳朵的话APP-1D3，[聆听]等和耳朵有关的技能全部-30%。",
    (1, 19) => "再投掷三次，由玩家选择其中一个作为特征。",
    (1, 20) => "再投掷三次，玩家和KP各选择一个特征。",
    (2, 1) => "再投掷一次，获得那个特征：特征具有(D)时，玩家可以再额外选择一个其他任意特征获得。特征没有(D)时，玩家必须再同时选择一个(D)特征。",
    (2, 2) => "诅咒(D)：调查员被吉普赛人，魔女，法师，外国原住民等施予了诅咒，诅咒效果等同[邪眼]咒文或者由KP决定。KP也可以决定解除诅咒的条件。",
    (2, 3) => "黑暗先祖(D)：调查员具有邪恶的一族，外国人，食人族，甚至神话生物的血统。投掷一个D100，出点越大，血统也越可怖。",
    (2, 4) => "听觉障碍(D)：[聆听]减少[1D4*5]%。",
    (2, 5) => "绝症缠身(D)：调查员身患绝症[癌症，失明，梅毒，结核等]，绝症对调查员造成恶劣影响，至少也失去了1点CON，如果病情继续恶化的话还会继续失去其他能力值。投掷一个D100来决定剩余寿命，出点越大寿命越长。",
    (2, 6) => "钟楼怪人(D)：调查员具有巨大的伤痕或者身体变形等特征，对APP造成至少减少1D4点影响。对交涉系技能也可能也造成影响[(失去的APP)*5%]。",
    (2, 7) => "酒豪：不易喝醉。酒精作为毒素处理的情况下， POT值只有他人的一半。",
    (2, 8) => "鹰眼：[侦察]增加[2D3*5]%。",
    (2, 9) => "敌人(D)：有对调查员不利的敌人存在，投掷一个D100来决定敌人的力量/数量，数值越大越恶劣。用途不限。",
    (2, 10) => "擅长武器：火器类射程+50%。近战类武器成功率+5%或者伤害增加1D2。并且武器不易被破坏(具有更多的耐久度)，或者入手的武器具有比一般的武器更高的品质。",
    (2, 11) => "传家宝：调查员拥有绘画，书籍，武器，家具等具有高价值的宝物。也可能是模组中追加的宝物的持有人。",
    (2, 12) => "俊足：DEX+1。再投掷一个D6，1~4时MOVE+1，5~6时MOVE+2。",
    (2, 13) => "赌徒(D?)：进行一次[幸运]鉴定。成功的话调查员获得[(INT+POW)*2]%的[赌博]技能。失败的话只有[INT或者POW*1]%的技能值，资产减少[1D6*10]%，并且调查员遇到赌博时需要通过一个SAN CHECK才能克制自己。",
    (2, 14) => "擅长料理：获得 [(INT或者EDU)*5]%的[手艺(料理)]技能。",
    (2, 15) => "听力良好：[聆听]+[2D3*5]%。",
    (2, 16) => "洞察人心：[心理学]+ [2D3*5]%。",
    (2, 17) => "反应灵敏：投掷1D6。1~3=DEX+1，4~5=DEX+2，6=DEX+3。",
    (2, 18) => "驱使动物：技能和动物有关时获得[(1D6+1)*5]的加值，例如骑马，驾驶马车，特定情况的藏匿，潜行等。",
    (2, 19) => "没有特征但是可以选择任意技能(可多选)获得总计3D20点技能加值。",
    (2, 20) => "玩家自己选择一个特征。",
    (3, 1) => "再投掷三次，玩家和KP各选择一个。",
    (3, 2) => "贪婪(D)：对调查员来说金钱至上。任何状况下都优先考虑金钱。为此欺骗他人也是正常的，欺骗对象也包含其他调查员。",
    (3, 3) => "悲叹人生：SAN-1D10，玩家和KP给调查员设定一个背景(失去爱人，子孙或者其他血亲的悲剧)。",
    (3, 4) => "憎恶(D)：玩家和KP商议决定，调查员对于特定的国籍，人种或者宗教具有无理由的反感。调查员接触此类人群时会表现出敌意。",
    (3, 5) => "比马还要健壮：CON+1D3。",
    (3, 6) => "快乐主义者：追求个人的喜悦(美食，饮品，性，衣装，音乐，家具等)。为此浪费了[(1D4+2)*10]%的资产。通过一个[幸运]鉴定，失败的话因为这种放纵的生活而失去1点STR，CON，INT，POW，DEX或者APP。",
    (3, 7) => "骑手：[骑马]技能+[(1D6+1)*10]%。",
    (3, 8) => "易冲动(D)：有不考虑后果轻率的行动的倾向。根据情况可能需要通过一个减半的[灵感]鉴定来使头脑冷静。",
    (3, 9) => "巧妙：二选一。A)[灵感]+10%，获得可以临时组装或者发明一些装置的能力。B)武器以外的操纵系技能获得加值，只选择一个技能的话+30%，选择2个技能各+20%，3个各+10%。",
    (3, 10) => "疯狂(D)：SAN-1D8。玩家和KP商议给予调查员一个精神障碍。",
    (3, 11) => "土地勘测员：调查员对某一篇地域了解的非常详细(例：建筑配置，道路，商业，住民，历史等)。对应的区域应为都市某一块区域或者单个农村之类的较狭小的范围。对于这篇区域的详细情况调查员通过[知识]或者[灵感]鉴定即可知晓。",
    (3, 12) => "意志顽强：POW+1D3，san也获得对应的上升。",
    (3, 13) => "花花公子：APP+1D3，和异性交往有关的交涉技能+[1D3*10]%。",
    (3, 14) => "持有高额财产：调查员拥有某种具有巨大价值的东西(例：船只，工厂，房屋，矿山，大块的土地等)。这些东西可能需要调查员花费很大的时间和精力在这里，玩家和KP要慎重的决定。",
    (3, 15) => "语言学家：调查员即使语言不通也有可能和对象成功的交流，增加一个辅助技能[语言学家]，初期技能值为[INT或者EDU*1]%。",
    (3, 16) => "家人失踪：调查员有着失踪很久的家人，有可能会在模组中登场(例：兄弟/姐妹/或者其他亲人遭遇海难，死在海外，被其他亲戚带走等情况)。",
    (3, 17) => "忠诚：调查员不会抛弃自己的家人，朋友，伙伴，在力所能及的范围内一定会帮助他们。这种性格也使他和自己周围的人群交涉时获得10%的加值。",
    (3, 18) => "魔术素质：学习咒文时只需要正常的一半时间，成功率也增加[INT*1]%。",
    (3, 19) => "虽然没有特侦但是职业技能值获得额外的3D20的技能点。",
    (3, 20) => "玩家自己选择一个特征。",
    (4, 1) => "虽然没有特征，但是调查员的持有现金为通常规则的2倍。",
    (4, 2) => "魔术道具：KP可以给予调查员一个魔术道具(可以杀伤神话生物的附魔武器，召唤神话生物的专用道具，占卜用品，POW储藏器等等)。调查员如果想要知道这件道具的详细性质需要通过一个[POW*1]的鉴定。",
    (4, 3) => "射击名人(手枪，步枪以及霰弹枪中选择一项)：选择的这项火器技能+[2D3*5]%。",
    (4, 4) => "认错人：调查员被频繁的被误认为其他人，通常都会是些有着恶评的人物(罪犯，身怀丑闻的恶人之类的)。模组中在合适的情况下[幸运]可能会被降为原本的一半(简单来说，调查员因为某些理由获得其他人的犯罪历史，恶名，通过诈骗获得的财富或者权力这样的身份或者特征)。",
    (4, 5) => "天气预报：通过一个[灵感]鉴定调查员就可以得知[1D6+1]小时里的正确天气情况。有多大的降雨量，下雨的场所，风级，持续时间等等。",
    (4, 6) => "对外观的强迫观念(D)：APP+1，但是调查员为了让自己看起来亮丽动人而花费大量的金钱来购买华贵的服饰和饰物。储蓄和资产减半。",
    (4, 7) => "古书：调查员拥有和模组有关的重要书籍资料或者它的复印(例：杂志，黑魔术书籍，历史书，圣经，神话魔导书，地图等等)。KP可以决定这件道具的性质和价值。",
    (4, 8) => "试炼生还者(D)：SAN-1D6。调查员拥有从恐怖环境中生还的经验(海难，战争，恐怖分子劫持，地震等等)。因为这个经历可能给调查员带来某种长久的影响(通常程度的恐怖症状，或者其他的精神障碍等)。",
    (4, 9) => "孤儿：调查员相依为命的家人都不在了，或者不知道自己真正的家人是谁。",
    (4, 10) => "其他语言：调查员可以追加获得一项其他语言技能。技能值为[1D4*INT]%。",
    (4, 11) => "野外活动爱好者：[导航]，[自然史]，[追踪]各增加[(2D3+1)*5]%(分别投掷)。",
    (4, 12) => "寄托爱意：模组中登场的某位角色对调查员怀有憧憬。由KP决定是哪位角色，为什么以及怀有何种程度。",
    (4, 13) => "身怀爱意(D)：调查员对其他角色怀有憧憬。由KP决定喜欢谁，为什么以及何种程度。",
    (4, 14) => "麻痹(D)：调查员因精神，疾病等原因苦于身体抽搐，扭曲等症状。各鉴定一次[幸运]，失败的话减少1D2点DEX和1点APP。",
    (4, 15) => "超常现象经历：调查员曾经经历过难以说明的遭遇(幽灵，黑魔术，神话生物，超能力等)。玩家和KP讨论决定其内容并失去最多1D6点SAN值。",
    (4, 16) => "大肚子(D)：这位调查员怎么说也太胖了点。鉴定一次[幸运]，失败的话投掷一个D6，1~3 CON-1，4~6 APP-1。",
    (4, 17) => "说服力：[劝说]+[(2D3+1)*5]%。",
    (4, 18) => "宠物：调查员有养狗，猫或者鸟类。",
    (4, 19) => "虽然没有特征但是任意技能获得3D20点技能点。",
    (4, 20) => "再投掷一次，获得那个特征：特征具有(D)时，玩家可以再额外选择一个其他任意特征获得。特征没有(D)时，玩家必须再同时选择一个(D)特征。",
    (5, 1) => "虽然没有特征但是职业技能值额外获得3D20点技能点。",
    (5, 2) => "恐怖症/疯狂(D)：调查员身患恐怖症状或者疯狂症状。参考6版标准规则随机决定症状，或者选择想要的症状。遭遇到自身症状根源的恐怖或者物品时，如果SAN CHECK失败，那么调查员将无法抑制自己的恐怖或者被魅惑。",
    (5, 3) => "权力/阶级/企业地位：调查员在政治，经济或者甚至军事环境里持有某种程度的权力。投掷D100，出点越大权力越大。企业地位影响融资，政治地位可能所属某种政府机关，军队地位远超本身拥有的军衔也说不定。[信用+25%。详细的情况和KP商议决定。",
    (5, 4) => "以前的经验：玩家可以选择获得[(INT或者EDU)*5]%的职业技能点数。",
    (5, 5) => "预知梦：由KP决定，游戏中玩家会做一个预言未来的梦。这大概会需要一个[POW*3]的鉴定。梦境没有必须符合现实的必要，如果梦境中见到的景象十分恐怖的话那么会失去一些SAN值(现实中见到相同景象失去SAN值的10%左右)。鉴定失败的话玩家会获得错误的预言。",
    (5, 6) => "繁荣：调查员的年收入和资产变成2倍。[信用]增加[1D4*5]%。调查员的事业很成功，或者调查员给富翁，持有权力的人做事或者与他们共事。",
    (5, 7) => "心理测量：接触某些物体时(或者抵达某个地方时)，通过一个POW*1的鉴定，成功的话可以窥视到这个物品/地方的过去。这个能力的正确度由KP决定。这个能力消耗1D6点MP。因为幻觉也可能失去SAN值(和上述的”预知梦”类似，损失通常的10%左右)。",
    (5, 8) => "健谈者：[快读交谈]+[2D4*5]%。调查员有着非常厉害的语言术，可以通过讲故事获得朋友的信任，降低敌人的敌意，赚到一顿免费的餐点也是可能的。",
    (5, 9) => "罕见的技能：调查员通过一个[INT*4]%的鉴定的话，可能会持有一些生活中完全不常见，或者一般来说不会有的技能。罕见的语言，格斗技，驾驶热气球之类，和KP商议决定。",
    (5, 10) => "红发：调查员有着一头好像燃烧着一般的红发，非常显眼(没有其他效果)。",
    (5, 11) => "评价(D?)：鉴定一次[幸运]。成功的话调查员被人尊敬(设定其理由)，调查员在自家所在的村子/都市中所有的交涉系技能获得15%的加值。[幸运]失败的话调查员获得极坏的评价，所有的交涉系技能-15%。KP也可以决定通过良好的业绩来抵消这个恶评。",
    (5, 12) => "报复追求者：调查员相信自己受到了不公正的待遇并且对导致自己受到这种恶意的对象进行报复行为。玩家和KP讨论决定敌人的真身。投掷一个D100来决定敌人的强度和调查员受到这种不公正的程度。",
    (5, 13) => "伤痕：鉴定一次[幸运]。成功的话伤痕没有影响调查员的外观，甚至彰显其英勇也说不定。失败的话失去1D3点APP，交涉系技能也减少[1D3*5]%。",
    (5, 14) => "科学的精神：[灵感]+5%。并且选择一个思考类技能+30%并再选择2个思考系技能+20%或者所有其他思考系技能+10%。",
    (5, 15) => "秘密(D?)：调查员有着决不能告诉别人的秘密。调查员的邻居可能会有些线索也说不定。调查员可能是个罪犯，间谍，或者卖国贼之类的也说不定。内容由玩家和KP商议决定。",
    (5, 16) => "秘密结社：调查员所属于秘密主义的团体，可能会是共济会，蔷薇十字团，神志主义者，炼金术师结社，光明会之类团体的一员。或者是地下医学研究者之类的犯罪/阴谋组织的一员。",
    (5, 17) => "自学：EDU+1D3，并增加因此获得的技能值。",
    (5, 18) => "可疑的过去/绯闻(D)：调查员过去曾经做过一些惹人怀疑的事情(卖淫，偷人等)，或者曾经犯下过某些重大罪行。所有的交涉系技能减少[1D3*10]%。",
    (5, 19) => "再投掷一次，获得那个特征：特征具有(D)时，玩家可以再额外选择一个其他任意特征获得。特征没有(D)时，玩家必须再同时选择一个(D)特征。",
    (5, 20) => "再投掷两次并获得那两个特征。",
    (6, 1) => "投掷三次，玩家和KP各选择一个特征。",
    (6, 2) => "病弱(D)：CON-1D3。",
    (6, 3) => "巧妙的手法：[钳工]技能增加[DEX*5]%，可以在偷窃或者魔术的时候使用。",
    (6, 4) => "迟缓(D)：MOVE-1。",
    (6, 5) => "失去名誉(D)：探索者因为国籍，性别，人种，宗教或者过去的犯罪记录等原因失去了社会上的名誉地位。作为其影响，调查员可能减少自由活动时间甚至所有的交涉系技能减少[1D4*10]%甚至更多。具体的影响玩家和KP商议决定。",
    (6, 6) => "原军人：调查员获得[INT*5]点的技能点加到士兵的职业技能上。",
    (6, 7) => "咒文知识：由KP决定!调查员最多可以获知1D3种咒文。SAN值减少1D6点。",
    (6, 8) => "胆小(D)：调查员见到血液或者流血就会感觉到身体不适，失去更多的SAN值。也可能因为疾病的原因无法靠近或通过流血现场。",
    (6, 9) => "坚毅：调查员不受到现实中的血迹或者流血的影响。遭遇血迹和流血时SAN损失为最小值，即使见到最残虐的场合(大量被撕裂的人，被猎奇杀死的尸体等)也最多只减少通常的一半。",
    (6, 10) => "比公牛还要强韧：STR+1D3。",
    (6, 11) => "迷信(D)：调查员迷信不疑，依赖着护身符，仪式或者愚蠢的信念。遭遇超自然现象的时候比通常多损失1点SAN值，即使原本不损失的情况下可能变成损失1点。",
    (6, 12) => "同情心：调查员选择一个交涉系技能+30%或者选择两个各+20%，然后额外再选择一个+10%。",
    (6, 13) => "意外的帮手：调查员因为一些缘由拥有一个对自己忠实并帮助自己的协助者。KP来决定这个协助者的真身和影响(依旧可以D100来决定)。并且D100也决定其频率。",
    (6, 14) => "看不见的财产：调查员有一笔自己不知道的财产。这可能是亲人遗赠的或者理事会之类授予的。这可能会是一块土地，房屋或者事业。这依旧可以用D100来决定去价值程度。",
    (6, 15) => "虚弱(D)：STR-1D3。",
    (6, 16) => "戴眼镜(D)：调查员要看清东西必须戴眼镜。鉴定一个[幸运]，成功的话眼镜只在读书或者进行精细工作的时候才需要。失败的话会在激烈运动等情况时会感觉到不能自由行动。不戴眼镜的话和视觉关联的技能减少[1D3*10]%(这个惩罚即使幸运成功也一样)。",
    (6, 17) => "彬彬有礼：调查员的[信用]+10%，真是个有礼貌的绅士(淑女)。",
    (6, 18) => "孩子(D)：调查员的年龄变成[10+2D3]岁。最大EDU变成[年龄的1/2+2]，DEX+1，STR，CON，APP中任意一项+1。玩家和KP商议决定，调查员大概依旧和家人住在一起，职业等也需要重新修正。",
    (6, 19) => "任意选择一项特征。",
    (6, 20) => "投掷两次，玩家任意选择其中一项特征。",
)

const superAdminList = [0xc45c1b20b131d1c8]
const superAdminQQList = [0x2151adb7df36d127]
const adminList = [0xc45c1b20b131d1c8, 0x192e269af0e0ce03]
const cmdList = [
    DiceCmd(:roll, r"^r(?:([ach]+)|(\d?)b|(\d?)p)*\s*(.*)", "骰点或检定", Set([:group, :private])),
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
    DiceCmd(:skillSet, r"^st( force)?\s*(.*)", "设定技能值", Set([:group, :private])),
    DiceCmd(:sanCheck, r"^sc\s*(.*)", "理智检定", Set([:group, :private])),
    DiceCmd(:skillEn, r"^en\s*(.*)", "技能成长", Set([:group, :private])),
    DiceCmd(:randomTi, r"^ti", "随机疯狂发作-即时症状", Set([:group, :private])),
    DiceCmd(:randomLi, r"^li", "随机疯狂发作-总结症状", Set([:group, :private])),
    DiceCmd(:randomGas, r"^gas", "随机煤气灯特质", Set([:group, :private])),
    DiceCmd(:jrrp, r"^jrrp", "今日人品", Set([:group, :private])),
    DiceCmd(:fuck2060, r"\u2060", "fuck\\u2060", Set([:group, :private])),
]

const helpText = """
    Dice Julian, made by 悟理(@phyxmeow).
    Version $diceVersion
    —————————————————
    目前可用的指令列表：
    .help 显示本条帮助
    .help links 一些有用的链接
    .bot [on/off/exit] 开关bot及让bot自动退群
    .r[c/a][b/p][h] 检定，使用规则书规则/通用房规，奖励骰/乘法骰，暗骰
    .r XdY  简单的骰骰子哒
    .coc [数量] 七版人物做成
    .jrrp 今日人品（据说数值越小越好）
    .pc [new/rm/nn/list] 人物卡管理，新建/删除/重命名/列表
    .ti/li 疯狂发作-即时/总结症状抽取
    .gas 煤气灯特质抽取\
    """
const helpLinks = """
    项目主页: https://github.com/PhyX-Meow/Dice.jl
    纯美苹果园: http://www.goddessfantasy.net/bbs/index.php
    魔都: https://cnmods.net/#/homePage
    骰声回响: https://dicecho.com/
    空白人物卡: https://1drv.ms/x/s!AnsQDRnK8xdggag-W_KjQsuJNU1Usw?e=H9MSPI
    守密人规则书: https://1drv.ms/b/s!AnsQDRnK8xdggZUiWCC3EsnUGpziEg?e=5mxIx5\
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
        "不准给我踏上阶梯半步！我在上面！而你在下面！",
    ],
)