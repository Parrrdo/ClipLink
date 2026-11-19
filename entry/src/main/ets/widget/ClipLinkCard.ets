/**
 * 云剪桌面服务卡片。
 *
 * 卡片本身没有窗口，点击按钮走 postCardAction({ action: 'message' })，
 * 由 ClipLinkFormAbility.onFormEvent 在卡片进程里直接执行，不会拉起任何界面。
 *
 * 注意：ArkTS 卡片运行在独立的卡片进程，不能引用本应用的业务代码，
 * 这里只负责画界面 + 发事件。
 */
const ACTION_UPLOAD: string = 'upload';
const ACTION_DOWNLOAD: string = 'download';

@Entry
@Component
struct ClipLinkCard {
  @LocalStorageProp('statusText') statusText: string = '就绪';
  @LocalStorageProp('busy') busy: boolean = false;

  private fire(action: string): void {
    postCardAction(this, {
      action: 'message',
      params: {
        clipAction: action
      }
    });
  }

  @Builder
  actionButton(icon: Resource, label: string, action: string) {
    Column() {
      Image(icon)
        .width(26)
        .height(26)
        .objectFit(ImageFit.Contain)
      Text(label)
        .fontSize(12)
        .fontColor('#E60A59F7')
        .margin({ top: 4 })
    }
    .width('100%')
    .height(72)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#1A0A59F7')
    .borderRadius(14)
    .opacity(this.busy ? 0.45 : 1)
    .onClick(() => {
      if (!this.busy) {
        this.fire(action);
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text('云剪')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#182431')
        Blank()
      }
      .width('100%')

      Text(this.statusText)
        .fontSize(11)
        .fontColor('#99182431')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
        .width('100%')

      Blank()

      Row({ space: 10 }) {
        Column() {
          this.actionButton($r('app.media.shortcut_upload'), '上传', ACTION_UPLOAD);
        }
        .layoutWeight(1)

        Column() {
          this.actionButton($r('app.media.shortcut_download'), '下载', ACTION_DOWNLOAD);
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#FAFFFFFF')
    .borderRadius(16)
  }
}
