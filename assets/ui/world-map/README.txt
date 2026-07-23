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
1. 欧洲遮罩已接入正式交互，承载欧洲势力板块。
2. 联合政府与俄罗斯不再作为独立势力或地图区域。
3. 亚洲遮罩的底图轮廓仍包含俄罗斯地理范围，但不再产生俄罗斯板块。
4. 南极洲当前仅保留为参考，不接入交互。
5. 遮罩为白色区域 + 透明背景，适合 Godot 中通过 modulate/self_modulate 动态着色。
