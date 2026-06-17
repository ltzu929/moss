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
1. 当前官网“分洲设色”图不能把俄罗斯作为独立区域识别。
2. 亚洲遮罩目前包含俄罗斯，游戏地图交互中俄罗斯归入亚洲。
3. 后续如果需要单独制作俄罗斯遮罩，应先从亚洲遮罩中扣除俄罗斯。
4. 欧洲和南极洲当前仅保留为参考，不建议接入交互。
5. 遮罩为白色区域 + 透明背景，适合 Godot 中通过 modulate/self_modulate 动态着色。
