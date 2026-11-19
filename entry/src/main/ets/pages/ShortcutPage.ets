/**
 * 快捷方式动作的占位页面。
 *
 * 它不做任何渲染（全透明、无交互），存在的唯一目的是让 ShortcutAbility 的窗口
 * 处于"已加载内容"的正常状态——只有这样窗口才能设置透明背景并正常弹出 toast。
 * 用户看到的始终是桌面，不会进入应用主界面。
 */
@Entry
@Component
struct ShortcutPage {
  build() {
    Stack() {
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
