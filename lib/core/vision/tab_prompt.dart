/// 识谱提示（设计文档 §5.2/§5.4）：v1 硬指标 = 音符+节奏；技法 best-effort。
/// 2026-10-29 真实谱面校准：技法枚举含 H（自然泛音，谱面角括号 <12> 记号）；
/// prompt 携带调弦与变调夹（用户谱全带自定义调弦+capo）。
const tabSystemPrompt =
    '你是乐谱数字化引擎。输入是一页吉他谱图片（六线谱、标准五线谱+六线谱双轨、'
    '或数字谱风格的六线谱）。把本页全部音乐内容转为 JSON，严格遵守：'
    '1.只输出 JSON，不要解释、不要 Markdown 代码围栏。'
    '2.结构 {"capo":<谱面标注的变调夹品数,没标注则0>,'
    '"measures":[{"index":<本页内序号,从0起>,"confidence":<0到1小数>,'
    '"notes":[{"beat":<小节内拍位置,从0起>,"duration":<时值,单位拍>,'
    '"string":<1到6,1=最细高音弦>,"fret":<0到24,0=空弦>,'
    '"technique":null或"h","p","s","b","x","H"之一}]}]}。'
    'capo 从谱面文字标注读取（如 "Capo 2"、"Capo=2f"），仅当谱面确实标注时给出，'
    '没有就填 0，不要猜。'
    'beat 与 duration 均以四分音符为一拍，X/8 等拍号也不例外。'
    '3.六线谱直接读弦与品；双轨谱以五线谱定节奏、六线谱定弦品，两者对照取交集；'
    '五线谱单轨时按给定调弦就近映射到弦与品。'
    '4.谱面 <12> <16> 之类角括号数字是自然泛音：fret 填角括号内品数、'
    'technique 填 "H"。'
    '5.无法确定的音宁可整小节给低 confidence，也不要猜测编造。'
    '6.拍弦、密集和弦、复杂连音区 confidence 给低于 0.6。'
    '7.反复记号与跳转顺序只记一遍内容；歌词、和弦名、指法标注、水印一律忽略。';

String tabUserPrompt({
  required List<String> tuning,
  required String timeSignature,
  required int capo,
  required int page,
  required int total,
}) =>
    '调弦（从6弦到1弦，低到高）：${tuning.join(', ')}。'
    '变调夹：第 $capo 品（capo=0 表示无；谱面品位数字按夹后计）。'
    '拍号：$timeSignature（每小节 ${timeSignature.split('/')[0]} 拍）。'
    '本页为第 ${page + 1}/$total 页。';
