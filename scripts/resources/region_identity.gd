## 内容身份的区域 ID 与显示名称映射。
## 运行时跨系统只传递 ID；显示层通过本类恢复玩家可见名称。
class_name RegionIdentity
extends RefCounted

const ID_BY_NAME: Dictionary = {
	"亚洲": "asia",
	"北美": "north_america",
	"欧洲": "europe",
	"非洲": "africa",
	"南美": "south_america",
	"大洋洲": "oceania",
}

const NAME_BY_ID: Dictionary = {
	"asia": "亚洲",
	"north_america": "北美",
	"europe": "欧洲",
	"africa": "非洲",
	"south_america": "南美",
	"oceania": "大洋洲",
}

const IDS = [
	"north_america",
	"south_america",
	"europe",
	"africa",
	"asia",
	"oceania",
]


static func display_name(region_id: String) -> String:
	return str(NAME_BY_ID.get(region_id, "未知地区"))


static func id_for_name(region_name: String) -> String:
	return str(ID_BY_NAME.get(region_name, ""))


static func is_valid_id(region_id: String) -> bool:
	return NAME_BY_ID.has(region_id)
