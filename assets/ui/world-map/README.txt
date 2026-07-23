MOSS 世界地图遮罩素材
=====================

源图：
- 6061682460.png：灰色世界轮廓图
- 6061670687.png：分洲设色图

统一裁切范围：
- left=222, top=222, right=1825, bottom=1226
- 输出尺寸：1603 × 1004
- 所有输出图片尺寸与坐标完全一致

可直接使用：
- world_land_mask.png
- world_outline_gray.png
- mask_north_america.png
- mask_south_america.png
- mask_africa.png
- mask_oceania.png
- mask_asia.png

参考层：
- mask_europe_reference.png
- mask_antarctica_reference.png

注意：
1. 欧洲遮罩已接入正式交互，承载合并后的抽象欧洲势力板块。
2. 联合政府与俄罗斯不再作为独立势力或地图区域。
3. 地图点击遵循大陆地理遮罩；亚洲遮罩仍包含俄罗斯地理范围，因此西伯利亚位置命中亚洲。
4. 西伯利亚相关事件可以把数值影响写入欧洲势力板块；这表示游戏归属，不表示欧洲拥有该地理区域，也不取代联合政府的组织身份。
5. 南极洲当前仅保留为参考，不接入交互。
6. 遮罩为白色区域 + 透明背景，适合 Godot 中通过 modulate/self_modulate 动态着色。
