import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { MultipartFormData } from './MultipartFormData'
import { IMAGE_CENSOR_BASE_URL as CENSOR_BASE_URL } from './ApiEndpoints'

const DOMAIN = 0x0000
const TAG = 'ImageCensorService'
const IMAGE_CENSOR_BASE_URL = CENSOR_BASE_URL

export interface ImageCensorResult {
  conclusion: string
  conclusionType: number
  log_id: number
  is_safe: boolean
  is_hit: boolean
  error_code?: number | null
  error_msg?: string | null
  data?: Object[]
}

export class ImageCensorService {
  static async checkLocalImage(imagePath: string): Promise<ImageCensorResult> {
    const realPath = ImageCensorService.normalizeLocalPath(imagePath)
    const formData = new MultipartFormData()
    formData.addFile('image', ImageCensorService.extractFilename(realPath), realPath, 'application/octet-stream')
    formData.addField('img_type', '0')

    const requestBody = await formData.build()
    const httpRequest = http.createHttp()

    try {
      const response = await httpRequest.request(`${IMAGE_CENSOR_BASE_URL}/check`, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': formData.getContentType() },
        extraData: requestBody,
        readTimeout: 30000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.OBJECT
      })

      if (response.responseCode === 200 || response.responseCode === 201) {
        return response.result as ImageCensorResult
      }

      hilog.error(DOMAIN, TAG, `Image censor failed: HTTP ${response.responseCode}, body=${JSON.stringify(response.result)}`)
      throw new Error('IMAGE_CENSOR_NETWORK_ERROR')
    } catch (err) {
      const error = err as BusinessError
      if ((err as Error).message === 'IMAGE_CENSOR_NETWORK_ERROR') {
        throw err as Error
      }
      hilog.error(DOMAIN, TAG, `Image censor error: ${error.message}`)
      throw new Error('IMAGE_CENSOR_NETWORK_ERROR')
    } finally {
      httpRequest.destroy()
    }
  }

  private static normalizeLocalPath(path: string): string {
    return path.startsWith('file://') ? path.substring(7) : path
  }

  private static extractFilename(path: string): string {
    const normalized = ImageCensorService.normalizeLocalPath(path)
    const slashIndex = normalized.lastIndexOf('/')
    return slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized
  }
}
