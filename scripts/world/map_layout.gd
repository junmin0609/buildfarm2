class_name MapLayout
extends RefCounted
## 글자로 그린 맵. 한 글자가 16px 타일 한 칸이다.
## 처음 배치는 tools/make_map.py 가 만들었다. ROWS 를 직접 고쳐도 되고, 새 MapLayout 을 만들어 지역을 늘려도 된다.
##
## 구역 (개울이 둘을 나누고 나무다리 길로 이어진다)
##   서쪽  개인 농장: 생산·농사·건설·자동화·꾸미기. 집 앞 흙밭(d) + 넓은 경작지(g), 울타리 없음
##   동쪽  메인 광장: 거래·NPC·시설. 분수 중심, 씨앗 상점·작물 판매처·게시판, 맨흙(x)은 새 시설 터
##   광장 북쪽·동쪽 길 끝 간판 = 다음 지역으로 나갈 자리
##
##   .  잔디          ,  꽃잔디        d  일궈 둔 흙밭 (경작 가능)   g  농장 경작지 (잔디, 경작 가능)
##   ~  물(못 지나감)  s  돌길          p  상점 앞 넓은 돌바닥
##   x  맨흙 자리      #  나무다리
##   =  가로 울타리   !  세로 울타리   +  울타리 기둥
##   T  나무   Y  어린 나무   B  덤불   R  바위   r  갈대(지나갈 수 있음)
##   b  나무통   c  사과 상자   f  꽃 화분   n  간판   (소품: PROPS 에 등록)
##   F  분수   Q  퀘스트 게시판   h  벤치   L  가로등
##   H  집 (왼쪽 위 기준 4x3칸)   M  잡화점 (4x3칸, 씨앗 사기 + 작물 팔기, 안에 들어가 NPC 와 거래)
##   J  기계상점 (3x2칸, 공장·자동화 기계를 아이템으로 판다, 안에 들어가 NPC 와 거래)
##   W  우물 (2x2칸, 물뿌리개를 채우는 곳)   O  출하함 (2x1칸, 하루가 끝나면 넣어 둔 것을 판다)
##   K  대장간 (3x2칸, 도구 강화)
##   C  레시피 상점 (3x2칸, 셰프 §71)
##   A  오래된 비행선 정류장 (4x3칸, §89. 복구하면 하늘섬으로 가는 비행선)
##   @  플레이어 시작 위치

const ROWS := [
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTpppTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTpppTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTT.B.TTTTTTTTTTTTTTTT~~~~TTT.TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTpppTnTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTYTTTTTTTTBY...BYB..Y.BB...B.TT~~~~TT..TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTpppTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTT....Y.B.....................TT~~~~TT...TT**T..TT...TT.TTTT.........T.ppp..TTTT....T*T.TT..T.T..TT**.TT...TTTT",
	"TTT......................,,,,.YTT~~~~TT...T****.......TT.T..T**T..T.....ppp.T..T..TT***T.TT....T...T***....TTTTT",
	"TTTY....H.......R........,,,,.BTT~~~~TT..T.****.............****........pGp.........****...........****...T.TTTT",
	"TTT................R....Y......TT~~~~TT.....**..............****.....T..ppp..........**.............**......TTTT",
	"TTT..O.f....B.W............B...TT~~~~TT............B....T....**.........ppp..Y..T...........Y...............TTTT",
	"TTTY......ss...................TT~~~~TTT..T.****........................ppp....................Y..........TTTTTT",
	"TTT.......@ss......ssssss.....BTTT~~~TTT.T..****................**......ppp.......................xxxxx.....TTTT",
	"TTTY.......sssssssssssssssss..BTTT~~~~TT..T.****....M.......B..****.....ppp....K.....J............xxxxx....TTTTT",
	"TTTB......................ssss.TTT~~~~TTT...****...............****.....ppp.......................xxxxx....TTTTT",
	"TTTB........................sssYTT~~~~TTT.T.....................**...T..ppp..................b....xxxxx.....TTTT",
	"TTT....gggggg.ddd..ggggggg...ss.TTT~~~~T.TT........1pppppp4.............ppp...2pppp5ppppppp3...............TTTTT",
	"TTT...gggggdddddddddgggggggg..ss.TT~~~~T.T9.......fppppppf..............ppp...ppppppcppppp6...............nTTTTT",
	"TTTY.ggggggdddddddddggggggggg..ss.B~~~~TTTT.....L....pppp.....L.........ppp..L.ppp....ppp....L..........L..TTTTT",
	"TTT..gggggdddddddddddggggggggg..sss####pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppssss",
	"TTT.gggggggdddddddddggggggggggg...s####pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppssss",
	"TTT.gggggggdddddddddggggggggggg..Tr~~~~pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppssss",
	"TTTBggggggggggdddgggggggggggggg.TTT~~~~TTT..............ppp.............ppp...ppp....ppp.......****........TTTTT",
	"TTT.gggggggggggggggggggggggggg..TTT~~~TTT.T...N..........pp..====......ppppppppp.....pp.........**=====....TTTTT",
	"TTTYggggggggggggggggggggggggggg.TTT~~~TTT...........B.............Q..ppppppppppp..........T.................TTTT",
	"TT...ggggggggggggggggggggggggg..TT~~~~TTTTT.........................ppppphppppppp...........................TTTT",
	"TT..ggggggggggggggggggggggggg..YTT~~~~TT.........Y.................pLpppppppppppLp...B............T..*......TTTT",
	"TT...ggggggggggggggggggggggggg.TTT~~~~TT.T...........=====...T....pppppPPpppPPppppp.....B..=====...........TTTTT",
	"TT...ggggggggggggggggggggggggg.TTT~~~TTT....**....................ppppPPppppppPpppp.........................TTTT",
	"TTY..gggggggggggggggggggggggg.YTT~~~~TTT.TT****..................ppppPpppppppppPpppp...............xxxxx..T.TTTT",
	"TT...gggggggggggggggggggggggg.TTT~~~~TT..T******..T..Y........*..ppppPpppppppppPpppp...........*...xxxxx....TTTT",
	"TT...ggggggggggggggggggggggg..TTT~~~TTT..TT*****.................ppppppppppppppppppppppppp7pp......xxxxx...TTTTT",
	"TTB.ggggggggggggggggggggggg...TT~~~~TTT....****..........**......phpppppppFppppphpppppppppppp......xxxxx....TTTT",
	"TTY.ggggggggggggggggggggggg...TT~~~~TT......**..........****..T..ppppppppppppppppppp.....pppppp.............TTTT",
	"TTY.gggggggggggggggggggggg....TT~~~~TT....T......*..B...****.....ppppPpppppppppPpppp.....pppppp...........T.TTTT",
	"TTT.gggggggggggggggggggg......TT~~~~TT...................**......ppppPpppppppppPpppp...............****...T.TTTT",
	"TTTT.ggggggggggggggg..........TT~~~~TT...T....B..................pppppPPppppppPpppp.....****.......****....TTTTT",
	"TTTTB~~~~~ggggggggg.......Y...TT~~~~TT.........................ppppppppPPpppPPppppp.....****..T....****.....TTTT",
	"TTTT~~~~~~~gggggg............YTT~~~~TT...T.........L..........ppppppLpppppppppppLppp....****.......****.....TTTT",
	"TTT.~~~~~~~gggg..............YTT~~~~TTT..T..........C.......pppppp..ppppphpppppppppppp..****...............TTTTT",
	"TTT..~~~~~..............B.....TT~~~~TTT..TT...............pppppp.....ppppppppppp..ppppp.........Y...........TTTT",
	"TT.....r...........R..........TTT~~~TTT.....xxxxx........ppppp.........ppppppp......ppppp............B..*...TTTT",
	"TT..BBYBY...................YYTTT~~~TTT..T..xxxxx..cppppfppp............ppp..........ppppp..................TTTT",
	"TTTTTTTTTT............TTTTTTTTTTT~~~TTT..T..xxxxx..pppppppp........T....ppp............ppppp...............TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTT.T.xxxxx......pp...............ppp........**...pLppp..........L..T.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT................xxxxx**.......ppp.......****....ppppppppppppp.....TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTT......**.......xxxxx***...B..ppp..T....****....ppppppppppppp....TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTT.....****......xxxxx***......ppp........**.....ppppA...ppppp...T.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT......****......xxxxx**.......ppp...............pppp....ppppp....TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT.=====.**..======....====...L.ppp..L..======....pppp....ppppp.===TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTT.............................ppp.........######ppppppppppppp....TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT.T.............................ppp.........##8###ppppppppppppp**.T.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT.........eeeeeeeeeee...........ppp......eee######eee..........**..TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT....eeeee~~~~~~~~~~~eeee.......ppp..eeee~~~~~~~~~~~~eeee.........T.eeee",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTeeeeee~~~~~~~~~~~~~~~~~~~~eeeeeee###ee~~~~~~~~~~~~~~~l~~~~eeeeeeeeeee~~~~",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TT~~~~~~~~l~~l~~~l~l~~l~~~~u~~~~~~~###~~~~~~~~~l~~~~~~~l~~~~~~~~~~~~~~~~~~~",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TT~~~~~~~~~~~~~~l~~~~~~u~~~~~~~~~~~###l~l~~~~~~l~~~~~~~l~~u~~~~~~~~~~~~~~~~",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TT~~~l~~~~l~~~~~~~~~~l~~~~~~~~~~~~~###~~~~~~~~~~~~~~~~~~~~~~~~u~~~~~~~~~l~~",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TT~~~~~~~l~l~...........l~~~~~~~~~~###~~~~~~............~~~~~~~~~~~l~~~~~~~",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TT~~~~~~....................~~~~~~~###~~....................~~~~~~~~~~~....",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TT......T.......T..T......TT.......ppp..T..............................TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT..T.TT..T..T.T..T..TTT..T.T....ppp...TTT..T.T....T.TT..T.....TTTTT.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
]

## 소품 글자 -> 소품 씬 (나무·바위 같이 한 칸에 놓이는 물체)
const PROPS := {
	"T": "res://scenes/props/tree.tscn",
	"R": "res://scenes/props/rock.tscn",
	"Y": "res://scenes/props/young_tree.tscn",
	"B": "res://scenes/props/bush.tscn",
	"r": "res://scenes/props/reeds.tscn",
	"F": "res://scenes/props/fountain.tscn",
	"Q": "res://scenes/props/board.tscn",
	"h": "res://scenes/props/bench.tscn",
	"L": "res://scenes/props/lamp.tscn",
	"b": "res://scenes/props/barrel.tscn",
	"c": "res://scenes/props/crate.tscn",
	"f": "res://scenes/props/flowerpot.tscn",
	"n": "res://scenes/props/sign.tscn",
	# 무드 개편 (아늑한 마을 광장): 화분·꽃밭·아치·팻말·이정표·칠판 간판·가게 앞 진열·노점·나루터·수련·오리
	"P": "res://scenes/props/planter.tscn",
	"*": "res://scenes/props/flowerbed.tscn",
	"G": "res://scenes/props/arch.tscn",
	"9": "res://scenes/props/farm_sign.tscn",
	"N": "res://scenes/props/signpost.tscn",
	"1": "res://scenes/props/chalk_seed.tscn",
	"2": "res://scenes/props/chalk_smith.tscn",
	"3": "res://scenes/props/chalk_gear.tscn",
	"4": "res://scenes/props/seed_cart.tscn",
	"5": "res://scenes/props/anvil.tscn",
	"6": "res://scenes/props/machine_crates.tscn",
	"7": "res://scenes/props/market_stall.tscn",
	"8": "res://scenes/props/dock_box.tscn",
	"l": "res://scenes/props/lily.tscn",
	"u": "res://scenes/props/duck.tscn",
}

## 소품·건물 글자 아래에 깔 바닥 (없으면 잔디)
## "p" 는 옆에 광장 돌바닥이 있을 때만 돌바닥 (아니면 잔디), "~" 물, "#" 나무 판자
const GROUND_UNDER := {"b": "p", "c": "p", "f": "p", "F": "p", "Q": "p", "h": "p", "L": "p", "M": "p",
	"P": "p", "G": "p", "9": "p", "N": "p", "1": "p", "2": "p", "3": "p", "4": "p", "5": "p", "6": "p", "7": "p",
	"8": "#", "l": "~", "u": "~"}

## 괭이로 갈 수 있는 땅 글자
const FARMABLE := ["d", "g"]
## 시설을 지을 수 있는 땅 글자 (지금은 농장 땅. 나중에 마을 시설 터 등을 넣을 수 있다)
const BUILDABLE := ["d", "g"]

## 건물 글자 -> 건물 씬
const BUILDINGS := {
	"H": "res://scenes/buildings/house.tscn",
	"M": "res://scenes/buildings/general_store.tscn",

	"W": "res://scenes/buildings/well.tscn",
	"O": "res://scenes/buildings/shipping_bin.tscn",
	"K": "res://scenes/buildings/blacksmith.tscn",
	"C": "res://scenes/buildings/recipe_shop.tscn",
	"A": "res://scenes/buildings/sky_station.tscn",
	"J": "res://scenes/buildings/machine_shop.tscn",
}


static func size() -> Vector2i:
	return Vector2i(ROWS[0].length(), ROWS.size())


static func char_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= ROWS.size() or cell.x < 0 or cell.x >= ROWS[cell.y].length():
		return ""
	return ROWS[cell.y][cell.x]
