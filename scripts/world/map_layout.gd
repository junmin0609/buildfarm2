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
##   H  집 (왼쪽 위 기준 4x3칸)   M  씨앗 상점 (3x2칸)   S  작물 판매처 (3x2칸)
##   @  플레이어 시작 위치

const ROWS := [
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTTTTTTTTTssTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTTTTTTTTTssTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTT.B.TTTTTTTTTTTTTTTT~~~~TTTB..Y..Y.TsTTTTTTTTTTTTTT",
	"TTTYTTTTTTTTBY...BYB..Y.BB...B.TT~~~~TT.........YsTTTY.....TTTTT",
	"TTT....Y.B.....................TT~~~~TT..........s..Y........BTT",
	"TTT......................,,,,.YTT~~~~TT..........s.n..........TT",
	"TTTY....H.......R........,,,,.BTT~~~~TTY.........ss....Y..B...TT",
	"TTT................R....Y......TT~~~~TT....,.Y...ss...........TT",
	"TTT....f....B..............B...TT~~~~TT...,,,,....ss...,,,,..BTT",
	"TTTY......ss...................TT~~~~TTTB.,,,,....ss...,,,,...TT",
	"TTT.......@ss......ssssss.....BTTT~~~TTT...,......ss.........YTT",
	"TTTY.......sssssssssssssssss..BTTT~~~~TTY.....B...ss..........TT",
	"TTTB......................ssss.TTT~~~~TTT.........ssS....xxxx.TT",
	"TTTB........................sssYTT~~~~TTT.M.......sbpppf.xxxxBTT",
	"TTT....gggggg.ddd..ggggggg...ss.TTT~~~~Tcppppf..Q.pppppppxxxxYTT",
	"TTT...gggggdddddddddgggggggg..ss.TT~~~~Tppppppp....ppppp.xxxx.TT",
	"TTTY.ggggggdddddddddggggggggg..ss.B~~~~TTpppppppppppp........YTT",
	"TTT..gggggdddddddddddggggggggg..sss####.ppppppppppppppp......BTT",
	"TTT.gggggggdddddddddggggggggggg...s####spLpppppppppppppp......TT",
	"TTT.gggggggdddddddddggggggggggg..Tr~~~~Bpppppppppppppppp....nBTT",
	"TTTBggggggggggdddgggggggggggggg.TTT~~~~TTppppppppppppppp.L....TT",
	"TTT.gggggggggggggggggggggggggg..TTT~~~TTT.pppppppFpppppppsssssss",
	"TTTYggggggggggggggggggggggggggg.TTT~~~TTT.ppppppppppppppppssssss",
	"TT...ggggggggggggggggggggggggg..TT~~~~TTT.ppppppppppppppppp...TT",
	"TT..ggggggggggggggggggggggggg..YTT~~~~TTY..phppppppppppppp....TT",
	"TT...ggggggggggggggggggggggggg.TTT~~~~TT.....pppppppppppp.....TT",
	"TT...ggggggggggggggggggggggggg.TTT~~~TTT.......L.s..h.p..x...BTT",
	"TTY..gggggggggggggggggggggggg.YTT~~~~TTTxxx.....ss.....xxxxx.TTT",
	"TT...gggggggggggggggggggggggg.TTT~~~~TTxxxxx....ss.....xxxxx.TTT",
	"TT...ggggggggggggggggggggggg..TTT~~~TTTxxxxx....s......xxxxx.TTT",
	"TTB.ggggggggggggggggggggggg...TT~~~~TTT.xxx.....s........x...TTT",
	"TTY.ggggggggggggggggggggggg...TT~~~~TT.,........s............TTT",
	"TTY.gggggggggggggggggggggg....TT~~~~TT,,,.......ss......,,,,YTTT",
	"TTT.gggggggggggggggggggg......TT~~~~TTY,,....T..ss......,,,,YTTT",
	"TTTT.ggggggggggggggg..........TT~~~~TT...........ss......,,.YTTT",
	"TTTTB~~~~~ggggggggg.......Y...TT~~~~TTY..........~s~~~~~.....TTT",
	"TTTT~~~~~~~gggggg............YTT~~~~TT.....Y.....~~~~~~~.....TTT",
	"TTT.~~~~~~~gggg..............YTT~~~~TTT..........~~~~~~~.....TTT",
	"TTT..~~~~~..............B.....TT~~~~TTT..........~~~~~~~r...YTTT",
	"TT.....r...........R..........TTT~~~TTT...........rr.rr......TTT",
	"TT..BBYBY...................YYTTT~~~TTT.........Y...Y..Y.YYYYTTT",
	"TTTTTTTTTT............TTTTTTTTTTT~~~TTT.....Y.TTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~TTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~~~TTTTTTTTTTTTTTTTTTTTTTTTTTT",
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
const GROUND_UNDER := {"b": "p", "c": "p", "f": "p", "F": "p", "Q": "p", "h": "p", "L": "p", "M": "p", "S": "p"}

## 괭이로 갈 수 있는 땅 글자
const FARMABLE := ["d", "g"]
## 시설을 지을 수 있는 땅 글자 (지금은 농장 땅. 나중에 마을 시설 터 등을 넣을 수 있다)
const BUILDABLE := ["d", "g"]

## 건물 글자 -> 건물 씬
const BUILDINGS := {
	"H": "res://scenes/buildings/house.tscn",
	"M": "res://scenes/buildings/shop_stall.tscn",
	"S": "res://scenes/buildings/sell_stand.tscn",
}


static func size() -> Vector2i:
	return Vector2i(ROWS[0].length(), ROWS.size())


static func char_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= ROWS.size() or cell.x < 0 or cell.x >= ROWS[cell.y].length():
		return ""
	return ROWS[cell.y][cell.x]
