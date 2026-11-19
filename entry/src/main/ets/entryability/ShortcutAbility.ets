import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import vibrator from '@ohos.vibrator';
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ConfigService } from '../services/ConfigService';
import { SyncClipboardService } from '../services/SyncClipboardService';
import { ClipboardUtil } from '../utils/ClipboardUtil';

const ACTION_UPLOAD = 'upload';
const ACTION_DOWNLOAD = 'download';
/** 震动开始后再退出，避免进程提前结束把震动打断 */
const EXIT_DELAY = 900;
/** 成功：一记短震；失败：两记短震 */
const VIBRATE_SHORT = 30;
const VIBRATE_GAP = 120;

/**
 * 桌面快捷方式专用 Ability。
 *
 * 目标：点「上传/下载剪贴板」时不进入应用主界面、桌面尽快恢复原样。
 *
 * 做法：onWindowStageCreate 一拿到窗口就 minimize()，连页面都不加载——
 * 实测 27ms 内窗口即被收进后台，系统的窗口过渡动画被压到最短；
 * 随后在后台完成网络 + 剪贴板操作，震动反馈，最后 terminateSelf()。
 *
 * 为什么无法做到"零闪动"：鸿蒙的桌面快捷方式（shortcuts_config.json）只能指向 UIAbility，
 * 而 UIAbility 必然创建窗口。窗口从创建到最小化之间，系统会给背后桌面叠一层模糊材质并播过渡动画，
 * 这一段由 window manager 控制，应用层无法关闭（setWindowFocusable(false) 也挡不住）。
 * 想要真正零窗口，只能改用桌面服务卡片（Form）作为入口。
 *
 * 该 Ability 运行在独立进程（module.json5 中 "process": ":shortcut"），
 * 其 AppStorage 与主界面进程互不干扰。
 */
export default class ShortcutAbility extends UIAbility {
  private action: string = '';
  private windowStage: window.WindowStage | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 服务层（ConfigService / ClipboardUtil）通过 AppStorage 取上下文
    AppStorage.setOrCreate('abilityContext', this.context);
    this.action = ShortcutAbility.readAction(want);
    console.info(`[ShortcutAbility] onCreate, action=${this.action}`);
  }

  /**
   * 常驻进程已存在时重复点击，参数从这里进来
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const action = ShortcutAbility.readAction(want);
    console.info(`[ShortcutAbility] onNewWant, action=${action}`);
    if (!action) {
      return;
    }
    this.action = action;
    this.hideWindow();
    void this.runOnce();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    // 窗口一创建就最小化：不加载任何页面，把系统过渡动画压到最短（实测 27ms 即收回后台）。
    // 万一 minimize 失败，退化成"加载透明页再最小化"。
    try {
      windowStage.getMainWindowSync().minimize().then(() => {
        console.info('[ShortcutAbility] early minimize ok');
      }).catch((error: BusinessError) => {
        console.warn(`[ShortcutAbility] early minimize failed: ${JSON.stringify(error)}`);
        this.loadTransparentPage(windowStage);
      });
    } catch (error) {
      console.warn('[ShortcutAbility] early minimize error:', JSON.stringify(error));
      this.loadTransparentPage(windowStage);
    }
    void this.runOnce();
  }

  private loadTransparentPage(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/ShortcutPage', (err: BusinessError) => {
      if (err.code) {
        console.error(`[ShortcutAbility] loadContent failed: ${JSON.stringify(err)}`);
        return;
      }
      try {
        windowStage.getMainWindowSync().setWindowBackgroundColor('#00000000');
      } catch (error) {
        console.warn('[ShortcutAbility] set transparent background failed:', JSON.stringify(error));
      }
      this.hideWindow();
    });
  }

  onWindowStageDestroy(): void {
    this.windowStage = undefined;
  }

  onDestroy(): void {
    console.info('[ShortcutAbility] onDestroy');
  }

  private static readAction(want: Want): string {
    try {
      const params = want?.parameters;
      const raw = params ? params['clipAction'] : undefined;
      if (typeof raw !== 'string') {
        return '';
      }
      if (raw === ACTION_UPLOAD || raw === ACTION_DOWNLOAD) {
        return raw;
      }
    } catch (error) {
      console.error('[ShortcutAbility] readAction error:', JSON.stringify(error));
    }
    return '';
  }

  /**
   * 把窗口收进后台。前台窗口会让系统模糊其背后的桌面，收走之后桌面立即恢复原状。
   */
  private hideWindow(): void {
    try {
      const mainWindow = this.windowStage?.getMainWindowSync();
      if (!mainWindow) {
        return;
      }
      mainWindow.minimize().then(() => {
        console.info('[ShortcutAbility] window minimized');
      }).catch((error: BusinessError) => {
        console.warn(`[ShortcutAbility] minimize failed: ${JSON.stringify(error)}`);
      });
    } catch (error) {
      console.warn('[ShortcutAbility] hideWindow error:', JSON.stringify(error));
    }
  }

  private async runOnce(): Promise<void> {
    let ok = false;
    try {
      await ConfigService.getInstance().loadConfig();
      const config = ConfigService.getInstance().getConfig();
      if (!config.server.url) {
        console.warn('[ShortcutAbility] server url is empty');
      } else {
        const service = new SyncClipboardService(
          config.server.url,
          config.server.username,
          config.server.password
        );
        if (this.action === ACTION_UPLOAD) {
          const text = await ClipboardUtil.getClipboardText();
          if (text) {
            await service.uploadTextContent(text);
            ok = true;
            console.info('[ShortcutAbility] upload done');
          } else {
            console.warn('[ShortcutAbility] clipboard is empty, nothing to upload');
          }
        } else if (this.action === ACTION_DOWNLOAD) {
          const text = await service.downloadTextContent();
          if (text) {
            await ClipboardUtil.setClipboardText(text);
            ok = true;
            console.info('[ShortcutAbility] download done');
          } else {
            console.warn('[ShortcutAbility] server has no text to download');
          }
        }
      }
    } catch (error) {
      console.error('[ShortcutAbility] runOnce error:', JSON.stringify(error));
    }

    await this.vibrateFeedback(ok);
    setTimeout((): void => {
      try {
        this.context.terminateSelf();
      } catch (error) {
        console.error('[ShortcutAbility] terminateSelf error:', JSON.stringify(error));
      }
    }, EXIT_DELAY);
  }

  private async vibrateFeedback(ok: boolean): Promise<void> {
    try {
      await vibrator.startVibration(
        { type: 'time', duration: VIBRATE_SHORT },
        { id: 0, usage: 'notification' }
      );
      if (!ok) {
        await new Promise<void>((resolve) => {
          setTimeout(resolve, VIBRATE_GAP);
        });
        await vibrator.startVibration(
          { type: 'time', duration: VIBRATE_SHORT },
          { id: 0, usage: 'notification' }
        );
      }
    } catch (error) {
      console.error('[ShortcutAbility] vibrate error:', JSON.stringify(error));
    }
  }
}
