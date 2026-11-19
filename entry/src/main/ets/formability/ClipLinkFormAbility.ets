import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formBindingData from '@ohos.app.form.formBindingData';
import formProvider from '@ohos.app.form.formProvider';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ConfigService } from '../services/ConfigService';
import { SyncClipboardService } from '../services/SyncClipboardService';
import { ClipboardUtil } from '../utils/ClipboardUtil';

const ACTION_UPLOAD: string = 'upload';
const ACTION_DOWNLOAD: string = 'download';

/**
 * 桌面服务卡片的执行端。
 *
 * 与 ShortcutAbility 的区别：卡片进程没有窗口，点击卡片按钮→onFormEvent→直接执行，
 * 全程不会出现任何窗口、模糊或过渡动画。
 */
export default class ClipLinkFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    console.info('[ClipLinkForm] onAddForm');
    return this.buildData('点按箭头同步剪贴板', false);
  }

  onFormEvent(formId: string, message: string): void {
    console.info(`[ClipLinkForm] onFormEvent formId=${formId} message=${message}`);
    void this.handle(formId, message);
  }

  onRemoveForm(formId: string): void {
    console.info(`[ClipLinkForm] onRemoveForm ${formId}`);
  }

  private buildData(statusText: string, busy: boolean): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData({
      statusText: statusText,
      busy: busy
    });
  }

  private static parseAction(message: string): string {
    try {
      const raw = JSON.parse(message) as Record<string, Object>;
      const action = raw['clipAction'];
      if (typeof action === 'string' && (action === ACTION_UPLOAD || action === ACTION_DOWNLOAD)) {
        return action;
      }
    } catch (error) {
      console.error('[ClipLinkForm] parseAction error:', JSON.stringify(error));
    }
    return '';
  }

  private async handle(formId: string, message: string): Promise<void> {
    const action = ClipLinkFormAbility.parseAction(message);
    if (!action) {
      return;
    }
    // 卡片进程与主界面不同进程，这里把卡片上下文注入给服务层（偏好存储要用）
    AppStorage.setOrCreate('abilityContext', this.context);

    await this.updateCard(formId, action === ACTION_UPLOAD ? '正在上传…' : '正在下载…', true);

    let ok = false;
    let detail = '';
    try {
      await ConfigService.getInstance().loadConfig();
      const config = ConfigService.getInstance().getConfig();
      if (!config.server.url) {
        detail = '未配置服务器';
      } else {
        const service = new SyncClipboardService(
          config.server.url,
          config.server.username,
          config.server.password
        );
        if (action === ACTION_UPLOAD) {
          const text = await ClipboardUtil.getClipboardText();
          if (text) {
            await service.uploadTextContent(text);
            ok = true;
            detail = `已上传 ${ClipLinkFormAbility.now()}`;
          } else {
            detail = '剪贴板为空或无法读取';
          }
        } else {
          const text = await service.downloadTextContent();
          if (text) {
            await ClipboardUtil.setClipboardText(text);
            ok = true;
            detail = `已复制 ${ClipLinkFormAbility.now()}`;
          } else {
            detail = '云端没有文本';
          }
        }
      }
    } catch (error) {
      console.error('[ClipLinkForm] handle error:', JSON.stringify(error));
      detail = '同步失败';
    }

    console.info(`[ClipLinkForm] result ok=${ok} detail=${detail}`);
    await this.updateCard(formId, detail, false);
  }

  private static now(): string {
    const date = new Date();
    const hh = date.getHours().toString().padStart(2, '0');
    const mm = date.getMinutes().toString().padStart(2, '0');
    return `${hh}:${mm}`;
  }

  private async updateCard(formId: string, statusText: string, busy: boolean): Promise<void> {
    if (!formId) {
      return;
    }
    try {
      await formProvider.updateForm(formId, this.buildData(statusText, busy));
    } catch (error) {
      const err = error as BusinessError;
      console.warn(`[ClipLinkForm] updateForm failed: ${err?.code} ${err?.message}`);
    }
  }
}
