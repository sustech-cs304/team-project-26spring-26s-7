import { ShareCallResult } from './ShareService'
import {
  ShareErrorCode,
  SharePreflightErrorCode,
  SharePreflightResult,
} from '../types/ShareTypes'

interface ShareMappedError {
  message: string
  detail?: string
}

export class ShareErrorMapper {
  static formatPreflight(result: SharePreflightResult): string {
    const mapped = ShareErrorMapper.mapPreflight(result)
    return ShareErrorMapper.join(mapped)
  }

  static formatPublishResult<T>(result: ShareCallResult<T>): string {
    const mapped = ShareErrorMapper.mapPublishResult(result)
    return ShareErrorMapper.join(mapped)
  }

  private static mapPreflight(result: SharePreflightResult): ShareMappedError {
    const code = result.errorCode ?? ''
    switch (code) {
      case SharePreflightErrorCode.CLOUD_ONLY_PHOTO:
        return {
          message: '该路线包含仅云端可用的照片，当前设备无法完整分享。',
          detail: '请先将这些照片恢复到本地，再重新发起分享。',
        }
      case SharePreflightErrorCode.LOCAL_PHOTO_MISSING:
        return {
          message: '部分照片在当前设备上不存在，无法完整分享该路线。',
          detail: '请确认照片仍保存在本机，或重新同步后再试。',
        }
      case SharePreflightErrorCode.PHOTO_SANITIZE_FAILED:
        return {
          message: '部分照片在分享前清洗失败，当前无法继续分享。',
          detail: '请稍后重试；如果仍失败，建议更换照片后再分享。',
        }
      case 'EMPTY_NODES':
        return {
          message: '该路线没有可分享的节点内容。',
        }
      case 'TOO_MANY_NODES':
        return {
          message: '路线节点过多，当前最多支持分享 30 个节点。',
          detail: '请减少节点数量后重试。',
        }
      case 'INVALID_PHOTO_COUNT':
        return {
          message: '路线图片数量校验失败，当前无法生成分享链接。',
          detail: '请重试分享；如果问题持续出现，请检查路线图片数据。',
        }
      case 'PHOTO_TOO_LARGE':
        return {
          message: '存在超过 20 MB 的图片，当前无法分享。',
          detail: '请删除大图或压缩后重试。',
        }
      case 'BODY_TOO_LARGE':
        return {
          message: '本次分享内容超过 100 MB，当前无法上传。',
          detail: '请减少图片数量或缩小图片体积后重试。',
        }
      case 'INVALID_EXPIRY':
        return {
          message: '分享有效期设置无效。',
          detail: '请重新选择有效期后再试。',
        }
      default:
        return {
          message: result.message ?? '分享前检查未通过。',
          detail: result.detail,
        }
    }
  }

  private static mapPublishResult<T>(result: ShareCallResult<T>): ShareMappedError {
    const code = result.errorCode ?? 0
    const messageKey = (result.errorMessage ?? '').toUpperCase()
    const detailKey = (result.errorDetail ?? '').toUpperCase()

    if (code === ShareErrorCode.INVALID_PHOTO_COUNT || messageKey === 'INVALID_PHOTO_COUNT') {
      return {
        message: '路线图片数量校验失败，当前无法生成分享链接。',
        detail: '请重试分享；如果问题持续出现，请检查路线图片数据。',
      }
    }
    if (code === ShareErrorCode.EMPTY_NODES || messageKey === 'EMPTY_NODES') {
      return {
        message: '该路线没有可分享的节点内容。',
      }
    }
    if (code === ShareErrorCode.TOO_MANY_NODES || messageKey === 'TOO_MANY_NODES') {
      return {
        message: '路线节点过多，当前最多支持分享 30 个节点。',
        detail: '请减少节点数量后重试。',
      }
    }
    if (code === ShareErrorCode.PHOTO_TOO_LARGE || messageKey === 'PHOTO_TOO_LARGE') {
      return {
        message: '存在超过 20 MB 的图片，当前无法分享。',
        detail: '请删除大图或压缩后重试。',
      }
    }
    if (code === ShareErrorCode.BODY_TOO_LARGE || messageKey === 'BODY_TOO_LARGE') {
      return {
        message: '本次分享内容超过 100 MB，当前无法上传。',
        detail: '请减少图片数量或缩小图片体积后重试。',
      }
    }
    if (code === ShareErrorCode.INVALID_JSON || messageKey === 'INVALID_JSON') {
      if (detailKey.indexOf('REPLACE') >= 0) {
        return {
          message: '旧链接替换校验失败，新链接未生成。',
          detail: '请重新生成分享链接后，再切换有效期。',
        }
      }
      return {
        message: '分享数据格式异常，当前无法生成分享链接。',
        detail: '请重试分享；如果问题持续出现，请检查路线内容。',
      }
    }
    if (code === ShareErrorCode.INVALID_EXPIRY || messageKey === 'INVALID_EXPIRY') {
      return {
        message: '分享有效期设置无效。',
        detail: '请重新选择有效期后再试。',
      }
    }
    if (code === ShareErrorCode.RATE_LIMITED || messageKey === 'RATE_LIMITED') {
      return {
        message: '分享请求过于频繁，请稍后再试。',
      }
    }
    if (messageKey === 'NETWORK_ERROR') {
      return {
        message: '网络异常，当前无法连接分享服务。',
        detail: '请检查网络后重试。',
      }
    }
    if (code === ShareErrorCode.INTERNAL_ERROR || messageKey === 'INTERNAL_ERROR') {
      return {
        message: '分享服务暂时异常，请稍后重试。',
      }
    }
    if (code >= 500) {
      return {
        message: '分享服务暂时异常，请稍后重试。',
      }
    }

    return {
      message: result.errorMessage ?? '生成分享链接失败。',
      detail: result.errorDetail,
    }
  }

  private static join(mapped: ShareMappedError): string {
    if (!mapped.detail) {
      return mapped.message
    }
    return `${mapped.message}\n${mapped.detail}`
  }
}
