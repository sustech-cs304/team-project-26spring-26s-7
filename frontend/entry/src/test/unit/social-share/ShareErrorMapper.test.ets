import { describe, it, expect } from '@ohos/hypium';
import { ShareErrorMapper } from '../../../main/ets/feature/social-share/services/ShareErrorMapper';
import {
  ShareErrorCode,
  SharePreflightErrorCode,
  type SharePreflightResult
} from '../../../main/ets/feature/social-share/types/ShareTypes';

function createPreflightResult(errorCode: string): SharePreflightResult {
  return {
    ok: false,
    errorCode,
    totalPhotoCount: 1,
    totalBytes: 0
  };
}

export default function shareErrorMapperTest() {
  describe('ShareErrorMapperTest', () => {
    it('formats cloud only preflight errors with detail line', 0, () => {
      const result = ShareErrorMapper.formatPreflight(
        createPreflightResult(SharePreflightErrorCode.CLOUD_ONLY_PHOTO)
      );
      expect(result.indexOf('\n') >= 0).assertTrue();
      expect(result.length > 10).assertTrue();
    });

    it('formats invalid expiry publish errors with detail line', 0, () => {
      const result = ShareErrorMapper.formatPublishResult<Object>({
        ok: false,
        errorCode: ShareErrorCode.INVALID_EXPIRY,
        errorMessage: 'INVALID_EXPIRY'
      });
      expect(result.indexOf('\n') >= 0).assertTrue();
      expect(result.length > 10).assertTrue();
    });

    it('passes through generic preflight message and detail', 0, () => {
      const result = ShareErrorMapper.formatPreflight({
        ok: false,
        errorCode: 'OTHER',
        message: 'fallback-message',
        detail: 'fallback-detail',
        totalPhotoCount: 0,
        totalBytes: 0
      });
      expect(result).assertContain('fallback-message');
      expect(result).assertContain('fallback-detail');
    });

    it('passes through generic publish message and detail', 0, () => {
      const result = ShareErrorMapper.formatPublishResult<Object>({
        ok: false,
        errorCode: 499,
        errorMessage: 'custom-error',
        errorDetail: 'custom-detail'
      });
      expect(result).assertContain('custom-error');
      expect(result).assertContain('custom-detail');
    });
  });
}
