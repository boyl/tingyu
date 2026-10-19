# 当前设计图标核对

核对依据：lib/ui/icons.dart、lib/ui/app.dart的modeIcon/ModeButton/transport/DownloadButton，以及lib/ui/theme.dart哔哩粉语义色。仅修改原型的资源读取，不修改上述运行时代码。

| 功能 | 当前资源 | 纠正内容 |
|---|---|---|
| 列表循环 | material/repeat | 去掉手绘双箭头，恢复当前工程字形和accent |
| 单曲循环 | material/repeat_one | 原字形含1，和列表模式区分 |
| 随机 | material/shuffle | 去掉手绘交叉箭头，使用当前工程字形 |
| 播完暂停 | material/looks_one_outlined | 优先复用现有字库，不新增自绘 |
| 下载 | download | 原圆角托盘箭头，普通text |
| 下载完成 | done | 原圆圈勾选，accent #fb7299，展示状态 |
| 播放/暂停 | play / pause | 原填充几何，按钮68，图形32，onPlayerButton |
| 上一首/下一首 | previous / next | 原路径坐标和竖线位置 |
| 队列 | queue | 原列表＋音符，含原椭圆音符 |
| 喜欢 | heart / heartFilled | 原贝塞尔路径，按状态轮廓/填充 |
| 歌词 | lyrics | 原圆角对话框，底部尖角路径 |
| 搜索 | search | 原圆心10.5、半径6.5与斜线 |
| 导航音乐/下载/喜欢 | music / download / heart | 资源读取替代原型近似路径 |
| 返回/收起/更多 | back / down / more | 原路径及实心圆点 |
| 文件夹/关于 | folder / info | 原路径/圆圈/实心信息点 |
| 倍速/时钟 | material/speed / material/schedule | 复用字库，不使用上一版手绘图标 |
| 头像/透明度/调节/存储 | 登记Material资源 | 原型从统一登记字体读取，设计复用状态明确 |

默认哔哩粉：模式/下载完成为#fb7299；不是正文强调色#a93660。其他主题以对应token读取，不能将原型色值散落到应用业务组件。

机器可验证来源、字形ID、色值、引用和目录一致；40个Painter SVG导出的像素级等价尚未进行Flutter渲染对比，不宣称原生图标验收通过。
