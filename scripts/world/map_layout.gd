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
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTsssTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTsssTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTT.B.TTTTTTTTTTTTTTTT~~~~TTT.TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTsssTnTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTYTTTTTTTTBY...BYB..Y.BB...B.TT~~~~TT..TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTsssTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTT....Y.B.....................TT~~~~TT...TT..T..TT...TT.TTTT.........T.ppp..TTTT....T.T.TT..T.T..TT...TT...TTTT",
	"TTT......................,,,,.YTT~~~~TT...T...........TT.T..T..T..T.....ppp.T..T..TT...T.TT....T...T.......TTTTT",
	"TTTY....H.......R........,,,,.BTT~~~~TT..T......,,,,....................ppp........,,,,...................T.TTTT",
	"TTT................R....Y......TT~~~~TT.........,,,,....................ppp........,,,,.....................TTTT",
	"TTT..O.f....B.W............B...TT~~~~TT.................B...............ppp.................................TTTT",
	"TTTY......ss...................TT~~~~TTT..T.............................ppp..R....R.......................TTTTTT",
	"TTT.......@ss......ssssss.....BTTT~~~TTT.T.................xxxxx.xxxxx..ppp...............T..xxxxx..xxxxx...TTTT",
	"TTTY.......sssssssssssssssss..BTTT~~~~TT..T...M............xxxxx.xxxxx..ppp..................xxxxx..xxxxx..TTTTT",
	"TTTB......................ssss.TTT~~~~TTT.............C....xxxxx.xxxxx..ppp....K......J......xxxxx..xxxxx..TTTTT",
	"TTTB........................sssYTT~~~~TTT.T........c.......xxxxx.xxxxx..ppp.........b......c.xxxxx..xxxxx...TTTT",
	"TTT....gggggg.ddd..ggggggg...ss.TTT~~~~T.TTppppppppppppppppppppppppppp..ppp..pppppppppppppppppppppppppppp..TTTTT",
	"TTT...gggggdddddddddgggggggg..ss.TT~~~~T.TTppppppppppppppppppppppppppp..ppp..pppppppppppppppppppppppppppp.nTTTTT",
	"TTTY.ggggggdddddddddggggggggg..ss.B~~~~TTTTppfppppppfpppppfppppppppppp..ppp..ppfppppppppppfpppppppfpppppp..TTTTT",
	"TTT..gggggdddddddddddggggggggg..sss####pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppssss",
	"TTT.gggggggdddddddddggggggggggg...s####pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppssss",
	"TTT.gggggggdddddddddggggggggggg..Tr~~~~pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppssss",
	"TTTBggggggggggdddgggggggggggggg.TTT~~~~TTT..............................ppp................................TTTTT",
	"TTT.gggggggggggggggggggggggggg..TTT~~~TTT.T..............L........Q.....ppp..............L.................TTTTT",
	"TTTYggggggggggggggggggggggggggg.TTT~~~TTT...............................ppp.................................TTTT",
	"TT...ggggggggggggggggggggggggg..TT~~~~TTTTT.........................ppppppppppp................B............TTTT",
	"TT..ggggggggggggggggggggggggg..YTT~~~~TT..........,,,,..........ppppppppppppppppppp..................R......TTTT",
	"TT...ggggggggggggggggggggggggg.TTT~~~~TT.T....T...,,,,.T......ppppppppppphppppppppppp.........,,,,.........TTTTT",
	"TT...ggggggggggggggggggggggggg.TTT~~~TTT............T.......ppppppppppppppppppppppppppp.......,,,,..........TTTT",
	"TTY..gggggggggggggggggggggggg.YTT~~~~TTT.TT...............ppppppppppppppppppppppppppppppp...Y..........T..T.TTTT",
	"TT...gggggggggggggggggggggggg.TTT~~~~TT..T...............ppphppppppppppppppppppppppppppppp.....R............TTTT",
	"TT...ggggggggggggggggggggggg..TTT~~~TTT..TT....T...B.....ppppppppppppppppppppppppppppppppL.................TTTTT",
	"TTB.ggggggggggggggggggggggg...TT~~~~TTT.................ppppppppppppppppppppppppppppppppppp.......B.........TTTT",
	"TTY.ggggggggggggggggggggggg...TT~~~~TT..................ppppppppppppppppppppppppppppppppppp.................TTTT",
	"TTY.gggggggggggggggggggggg....TT~~~~TT....T..,,,,Y..B...pppppppppppppppppFppppppppppppppppp...............T.TTTT",
	"TTT.gggggggggggggggggggg......TT~~~~TT.......,,,,.......pppppppphpppppppppppppppppphppppppp...............T.TTTT",
	"TTTT.ggggggggggggggg..........TT~~~~TT...T..............ppppppppppppppppppppppppppppppppppp....T...........TTTTT",
	"TTTTB~~~~~ggggggggg.......Y...TT~~~~TT...........Y...R..ppppppppppppppppppppppppppppppppppp.................TTTT",
	"TTTT~~~~~~~gggggg............YTT~~~~TT...T...............ppppppppppppppppppppppppppppppppp........,,,,......TTTT",
	"TTT.~~~~~~~gggg..............YTT~~~~TTT..T...............pLppppppppppppppppppppppppppppppp........,,,,.....TTTTT",
	"TTT..~~~~~..............B.....TT~~~~TTT..TT..Y........R...ppppppppppppppppppppppppppppphp......B............TTTT",
	"TT.....r...........R..........TTT~~~TTT.....................ppppppppppppppppppppppppppp.....................TTTT",
	"TT..BBYBY...................YYTTT~~~TTT..T.........B..........ppppppppppphppppppppppp.......................TTTT",
	"TTTTTTTTTT............TTTTTTTTTTT~~~TTT..T......................ppppppppppppppppppp..........T....B....Y...TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTT.T.............B...........ppppppppppp...........................T.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT..............................ppp.................................TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTT..xxxxxx.....................ppp.............L..............L...TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTT..xxxxxx...Y.......Y.........ppp......B......pppppppppppppppp..T.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT...xxxxxx................Y....ppp.............pppppppppppppppp...TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT...xxxxxx........Y...........Lppp.L...........ppcpppAppppppbpp...TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTT..xxxxxx..T.....,,,,.........ppp.........T...pppppppppppppppp...TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT.T................,,,,.........ppp.............pppppppppppppppp..T.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT...............................ppp.............pppppppppppppppp...TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT........................T..T...ppp.............pppppppppppppppp..T.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT...xxxxxx....xxxxxx...........ppp.......Y.....pppppppppppppppp...TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT....xxxxxx....xxxxxx...........ppp..T...,,,,Y.....................TTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT...xxxxxx....xxxxxx......T..n.ppp......,,,,.....................T.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT...xxxxxx....xxxxxx...........ppp......B.........T.......T,,,,....TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT....xxxxxx....xxxxxx.........~~~~~~~........R..............,,,,....TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTT...........................~~~~~~~~~..............................TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTT.TT.......T..T......TT...~~~~~~~~~~~......................T.T..TTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTT..T.TT..T..T.T..T..TTT..T.T.~~~~~~~~~TTT..T.T....T.TT..T.....TTTTT.TTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
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
}

## 소품·건물 글자 아래에 깔 바닥 (없으면 잔디)
const GROUND_UNDER := {"b": "p", "c": "p", "f": "p", "F": "p", "Q": "p", "h": "p", "L": "p", "M": "p"}

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
