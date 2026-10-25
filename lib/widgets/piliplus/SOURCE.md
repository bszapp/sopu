# PiliPlus 详情页移植来源

源目录：D:/prompt-test/ref/PiliPlus/PiliPlus-main。许可证全文见 LICENSE。

- score_detail_layout.dart：先复制 lib/pages/video/view.dart，提取并改造 childWhenDisabled、_childWhenDisabledLandscapeInner、buildTabBar、videoIntro 的布局；播放器替换为谱面，B 站控制器替换为曲谱回调。竖屏简介后包含推荐，横屏左侧谱面与简介、右侧推荐/评论。
- score_intro_panel.dart：先复制 lib/pages/video/introduction/ugc/view.dart，保留作者、标题、统计、展开说明、actionGrid 排列，替换曲谱字段。删除不适用于曲谱的投币、点踩、弹幕、番剧、分 P、赞助片段分支。
- 其余 Dart 文件直接复制自各文件首行所示源路径；仅替换 Flutter Material、相对导入及必要的类型兼容。ActionItem 的图标使用现有 Material 图标。
- MiniScaffold 在原项目服务视频内嵌底部弹层，此处使用 Material 容器；搜谱仍由现有全局播放器管理底部播放面板。
- packages/extended_nested_scroll_view：来自参考项目 pubspec.lock 指定的 d9136d5d85f41cd92f80771b84ef7c9d4c97e95c（6.2.1）。保留原滚动协调算法，仅将 material_ui 导入替换为 Flutter Material，并去除未使用的两项 UI 包依赖。许可证保留在包目录。

- score_related_panel.dart：先复制 lib/pages/video/related/view.dart，保留 SliverPadding/SliverGrid 和状态分支；虫虫接 getRecommendByOpernId，弹琴吧接同标题搜索及作者其它谱。

- score_reply_item.dart：先复制 lib/pages/video/reply/widgets/reply_item_grpc.dart，保留 build、header、content、buttonAction 的布局与间距；gRPC 实体映射为已有评论字段，保留本人删除、回复和状态回读。TranslucentRow 直接复制。

- main_layout.dart、slotted_layout_helper.dart：直接复制原文件。按用户新增要求，将 body 的高度改为扣除 bottomNav 实际高度；app_shell.dart 的位移采用 pages/main/view.dart 原 FractionalTranslation 分支及原 500ms/easeInOutCubicEmphasized 动画参数，导航和播放栏合并测量。移除详情原末尾占位及推荐底部 100 像素占位。

- author_page.dart：移植 pages/member/view.dart 的 Material → ExtendedNestedScrollView → DynamicSliverAppBar.medium → TabBar/TabBarView 主体，以及 member_favorite/view.dart 的保持存活列表；只替换账号控制器和发布/收藏请求。两个标签独立保存分页及滚动状态。
- member_info_card.dart：移植 pages/member/widget/user_info_card.dart 的 _buildV、_buildH、_buildRight、_buildName、_buildSign 和头像边框；删除直播、充电、私信等两平台没有的分支。
- member_header_layout.dart、dynamic_sliver_app_bar/ 三文件、custom_height_widget.dart、only_layout_widget.dart：直接复制，只替换导入。
- score_card_h.dart / score_card_v.dart：移植 common/widgets/video_card/video_card_h.dart / video_card_v.dart 的 build、content、统计排列。替换曲谱数据、徽标和跳转，移除 B 站视频菜单。搜索、相关推荐及主页推荐复用对应卡片。
- search_page.dart：TabBar 装饰及横卡网格来自 pages/search_result/view.dart、pages/search_panel/video/view.dart；平台过滤替换 B 站分类，尾部自动分页。
- score_detail_layout.dart：补回 video/view.dart 的全区域主题色透明覆盖、状态栏渐变和 childSplit。谱面宽高比由 Dart 解码图片取得。
- score_reply_item.dart：补回原 replyItemRow 灰底两行回复预览、完整楼层面板、长按菜单和 zan_grpc.dart 的图标加数字排布；列表与楼层尾部自动分页。弹琴吧无父评论 ID 的行保留其明确的“回复某人”目标。
- text_more/、flutter/text/text.dart：复制原 TextMore、RichTextMore、RenderParagraphMore、BaseText。Flutter Material 未公开原 fork 的 textPainter，兼容层使用同参数 TextPainter 测量；文本间距工具从当前 Flutter text.dart 原样补入。Flutter 来源许可证保留于 flutter/LICENSE。
- num_utils.dart：复制 utils/num_utils.dart，所有统计数字沿用同一万/亿格式。
- ../player_bar.dart：试听面板移植 pages/audio/view.dart 的 build、_buildInfo、_buildDuration、_buildControls 排列，保留已有单曲播放服务，省略没有队列数据的前后曲目功能。
- image_viewer/：直接复制 common/widgets/image_viewer/gallery_viewer.dart、viewer.dart、image.dart、loading_indicator.dart、hero_dialog_route.dart，以及三种图片手势识别器、横向识别器、colored_box_transition.dart 和 simple_dialog_option.dart。保留原全屏黑底、底部页码、双击/双指缩放、图片边缘翻页、惯性移动、拖动退出和淡出动画。删除 B 站缩略图质量、Live Photo、分享/链接菜单，接入现有图片字节与相册保存。当前 Flutter 的 PageView 未公开原项目的识别器工厂，兼容层仅在布局阶段连接现有 Scrollable 手势工厂，滚动和翻页回调仍由 Flutter 管理；DoubleTap 私有 hook 改用公开回调记录同一事件时间戳。Flutter image.dart 许可证见 flutter/LICENSE。详情区原右上角页码组件独立保留。
