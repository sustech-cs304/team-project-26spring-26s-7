import { describe, it, expect } from '@ohos/hypium';
import { http } from '@kit.NetworkKit';
import {
  SharePhoto,
  ShareService,
} from '../../../main/ets/feature/social-share/services/ShareService';
import { MultipartFormData } from '../../../main/ets/common/api/MultipartFormData';
import {
  type ReplaceLink,
  type ReplayPrefsForShare,
  type RevokeByTripOk,
  type SharePublishOk,
  type SharePublishNode,
  type SharePublishRequest,
  type ShareStatusOk,
} from '../../../main/ets/feature/social-share/types/ShareTypes';

interface RecordedField {
  name: string
  value: string
}

interface RecordedFile {
  name: string
  filename: string
  filePath: string
  contentType: string
}

class FakeMultipartFormData extends MultipartFormData {
  capturedFields: RecordedField[] = []
  capturedFiles: RecordedFile[] = []
  payload: ArrayBuffer = new ArrayBuffer(8)

  addField(name: string, value: string): void {
    this.capturedFields.push({ name, value })
  }

  addFile(name: string, filename: string, filePath: string, contentType: string = 'application/octet-stream'): void {
    this.capturedFiles.push({ name, filename, filePath, contentType })
  }

  getContentType(): string {
    return 'multipart/form-data; boundary=test-boundary'
  }

  async build(): Promise<ArrayBuffer> {
    return this.payload
  }
}

interface FakeHttpResponse {
  responseCode: number
  result: Object | string | ArrayBuffer | undefined
}

interface PublishEnvelope {
  code: number
  message?: string
  detail?: string
  data?: SharePublishOk
}

interface StatusEnvelope {
  code: number
  message?: string
  detail?: string
  data?: ShareStatusOk
}

interface RevokeEnvelope {
  code: number
  message?: string
  detail?: string
  data?: RevokeByTripOk
}

class TestShareService extends ShareService {
  form: FakeMultipartFormData = new FakeMultipartFormData()
  responseCode: number = 201
  responseResult: Object | string | ArrayBuffer | undefined = undefined
  requestError?: Error
  requestCount: number = 0
  lastUrl: string = ''
  lastOptions?: http.HttpRequestOptions

  protected createFormData(): MultipartFormData {
    return this.form
  }

  protected async sendRequest(url: string, options: http.HttpRequestOptions): Promise<http.HttpResponse> {
    this.requestCount += 1
    this.lastUrl = url
    this.lastOptions = options
    if (this.requestError) {
      throw this.requestError
    }
    const response: FakeHttpResponse = {
      responseCode: this.responseCode,
      result: this.responseResult,
    }
    return response as http.HttpResponse
  }
}

function createTrip(photoCount: number = 1): SharePublishRequest {
  const nodes: SharePublishNode[] = [{
    id: 'node-1',
    title: 'Node 1',
    content: 'Content 1',
    poiName: 'POI 1',
    photoCount,
    mood: 'calm',
    tags: ['tag'],
    visitedAt: 1715000000000,
    nodeOrder: 0
  }]
  return {
    tripId: 'trip-1',
    tripName: 'Trip 1',
    totalDistance: 42,
    coverIndex: 0,
    createdAt: 1715000000000,
    nodes
  }
}

function createPhotos(count: number): SharePhoto[] {
  const photos: SharePhoto[] = []
  for (let i = 0; i < count; i++) {
    photos.push({
      filePath: `/share/photo-${i}.jpg`,
      filename: `photo-${i}.jpg`,
      contentType: 'image/jpeg'
    })
  }
  return photos
}

function findField(form: FakeMultipartFormData, name: string): string {
  for (let i = 0; i < form.capturedFields.length; i++) {
    if (form.capturedFields[i].name === name) {
      return form.capturedFields[i].value
    }
  }
  return ''
}

export default function shareServiceTest() {
  describe('ShareServiceTest', () => {
    it('rejects mismatched photo count before sending request', 0, async () => {
      const service = new TestShareService()
      const result = await service.publish(createTrip(2), createPhotos(1), 24)

      expect(result.ok).assertFalse()
      expect(result.errorMessage).assertEqual('INVALID_PHOTO_COUNT')
      expect(service.requestCount).assertEqual(0)
    })

    it('builds publish request with expiry minutes replace and replay prefs', 0, async () => {
      const service = new TestShareService()
      const publishOk: SharePublishOk = {
        url: 'https://example.com/s/abc12345',
        shortCode: 'abc12345',
        expiresAt: 1716000000,
        sig: 'deadbeef',
        coverPhotoUrl: 'https://example.com/cache/cover.webp'
      }
      const envelope: PublishEnvelope = {
        code: 0,
        data: publishOk
      }
      service.responseResult = envelope

      const replace: ReplaceLink = {
        shortCode: 'old12345',
        expirySec: 1715900000,
        sig: 'oldsig'
      }
      const replayPrefs: ReplayPrefsForShare = {
        styleKitId: 'minimal_white',
        bgmId: 'city_lights_lofi',
        filterId: 'warm',
        transitionType: 'fade',
        enableBlurOverlay: true,
        enableRouteAnimation: false,
        enableRipple: true
      }

      const result = await service.publish(createTrip(2), createPhotos(2), 24, 5, replace, replayPrefs)

      expect(result.ok).assertTrue()
      expect(service.lastUrl).assertContain('/api/v1/share/publish')
      expect(service.requestCount).assertEqual(1)
      expect(service.form.capturedFiles.length).assertEqual(2)
      expect(service.form.capturedFiles[0].name).assertEqual('photo_0')
      expect(service.form.capturedFiles[1].name).assertEqual('photo_1')
      expect(findField(service.form, 'expiryMinutes')).assertEqual('5')
      expect(findField(service.form, 'expiryHours')).assertEqual('')
      expect(findField(service.form, 'replaceShortCode')).assertEqual('old12345')
      expect(findField(service.form, 'replaceExpiry')).assertEqual('1715900000')
      expect(findField(service.form, 'replaceSig')).assertEqual('oldsig')
      expect(findField(service.form, 'replayStyleKitId')).assertEqual('minimal_white')
      expect(findField(service.form, 'replayBgmId')).assertEqual('city_lights_lofi')
      expect(findField(service.form, 'replayFilterId')).assertEqual('warm')
      expect(findField(service.form, 'replayTransitionType')).assertEqual('fade')
      expect(findField(service.form, 'replayEnableBlurOverlay')).assertEqual('true')
      expect(findField(service.form, 'replayEnableRouteAnimation')).assertEqual('false')
      expect(findField(service.form, 'replayEnableRipple')).assertEqual('true')
    })

    it('falls back to expiry hours and omits optional publish fields when not provided', 0, async () => {
      const service = new TestShareService()
      const publishOk: SharePublishOk = {
        url: 'https://example.com/s/hours1234',
        shortCode: 'hours1234',
        expiresAt: 1717000000,
        sig: 'sig-hours',
        coverPhotoUrl: ''
      }
      const envelope: PublishEnvelope = {
        code: 0,
        data: publishOk
      }
      service.responseResult = envelope

      const replace: ReplaceLink = {
        shortCode: '',
        expirySec: 0,
        sig: ''
      }

      const result = await service.publish(createTrip(3), createPhotos(3), 72, undefined, replace)

      expect(result.ok).assertTrue()
      expect(findField(service.form, 'expiryHours')).assertEqual('72')
      expect(findField(service.form, 'expiryMinutes')).assertEqual('')
      expect(findField(service.form, 'replaceShortCode')).assertEqual('')
      expect(findField(service.form, 'replaceExpiry')).assertEqual('')
      expect(findField(service.form, 'replaceSig')).assertEqual('')
      expect(findField(service.form, 'replayStyleKitId')).assertEqual('')
      expect(service.form.capturedFiles.length).assertEqual(3)
      expect(service.form.capturedFiles[0].name).assertEqual('photo_0')
      expect(service.form.capturedFiles[0].filePath).assertEqual('/share/photo-0.jpg')
      expect(service.form.capturedFiles[1].name).assertEqual('photo_1')
      expect(service.form.capturedFiles[1].filePath).assertEqual('/share/photo-1.jpg')
      expect(service.form.capturedFiles[2].name).assertEqual('photo_2')
      expect(service.form.capturedFiles[2].filePath).assertEqual('/share/photo-2.jpg')
    })

    it('returns parsed backend error for failed publish', 0, async () => {
      const service = new TestShareService()
      service.responseCode = 400
      const envelope: PublishEnvelope = {
        code: 40003,
        message: 'INVALID_EXPIRY',
        detail: 'expiry out of range'
      }
      service.responseResult = envelope

      const result = await service.publish(createTrip(1), createPhotos(1), 24)

      expect(result.ok).assertFalse()
      expect(result.errorCode).assertEqual(40003)
      expect(result.errorMessage).assertEqual('INVALID_EXPIRY')
      expect(result.errorDetail).assertContain('expiry out of range')
    })

    it('maps request exceptions to network error during publish', 0, async () => {
      const service = new TestShareService()
      service.requestError = new Error('socket closed')

      const result = await service.publish(createTrip(1), createPhotos(1), 24)

      expect(result.ok).assertFalse()
      expect(result.errorMessage).assertEqual('NETWORK_ERROR')
      expect(result.errorDetail).assertContain('socket closed')
    })

    it('parses share status success envelope', 0, async () => {
      const service = new TestShareService()
      service.responseCode = 200
      const statusOk: ShareStatusOk = {
        shortCode: 'abc12345',
        expiresAt: 1716000000,
        remainingSeconds: 300,
        publishedAt: 1715999700
      }
      const envelope: StatusEnvelope = {
        code: 0,
        data: statusOk
      }
      service.responseResult = envelope

      const result = await service.status('abc12345')

      expect(result.ok).assertTrue()
      expect(result.data?.shortCode).assertEqual('abc12345')
      expect(service.lastUrl).assertContain('/abc12345/status')
    })

    it('maps share status error envelopes', 0, async () => {
      const service = new TestShareService()
      service.responseCode = 404
      const envelope: StatusEnvelope = {
        code: 40404,
        message: 'NOT_FOUND_OR_EXPIRED',
        detail: 'short code not found'
      }
      service.responseResult = envelope

      const result = await service.status('missing123')

      expect(result.ok).assertFalse()
      expect(result.errorCode).assertEqual(40404)
      expect(result.errorMessage).assertEqual('NOT_FOUND_OR_EXPIRED')
    })

    it('parses revoke by trip success envelope', 0, async () => {
      const service = new TestShareService()
      service.responseCode = 200
      const revokeOk: RevokeByTripOk = {
        tripId: 'trip-1',
        revokedCount: 2
      }
      const envelope: RevokeEnvelope = {
        code: 0,
        data: revokeOk
      }
      service.responseResult = envelope

      const result = await service.revokeByTrip('trip-1')

      expect(result.ok).assertTrue()
      expect(result.data?.revokedCount).assertEqual(2)
      expect(service.lastUrl).assertContain('/api/v1/share/revoke-by-trip')
    })
  })
}
