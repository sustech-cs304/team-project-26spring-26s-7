import { describe, it, expect } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import {
  SharePhotoHelper,
  type SharePhotoHelperHooks,
} from '../../../main/ets/feature/social-share/services/SharePhotoHelper';
import type { SharePhoto } from '../../../main/ets/feature/social-share/services/ShareService';
import { SharePreflightErrorCode } from '../../../main/ets/feature/social-share/types/ShareTypes';

function createCtx(): common.UIAbilityContext {
  return {} as common.UIAbilityContext
}

function createTempPhotos(): SharePhoto[] {
  return [
    {
      filePath: '/tmp/a.jpg',
      filename: 'a.jpg',
      contentType: 'image/jpeg',
      cleanupPath: '/tmp/a.jpg'
    },
    {
      filePath: '/tmp/b.jpg',
      filename: 'b.jpg',
      contentType: 'image/jpeg'
    },
    {
      filePath: '/tmp/c.jpg',
      filename: 'c.jpg',
      contentType: 'image/jpeg',
      cleanupPath: '/tmp/c.jpg'
    }
  ]
}

export default function sharePhotoHelperTest() {
  describe('SharePhotoHelperTest', () => {
    it('skips cloud only refs and missing local files', 0, () => {
      const photos = SharePhotoHelper.toSharePhotos([
        'users/demo/photo.jpg',
        'cloud://album/photo.jpg',
        'entry/src/test/fixtures/share/missing-photo.jpg'
      ])

      expect(photos.length).assertEqual(0)
    })

    it('ignores empty path entries', 0, () => {
      const photos = SharePhotoHelper.toSharePhotos(['', 'users/demo/photo.jpg'])

      expect(photos.length).assertEqual(0)
    })

    it('collects cloud only missing and sanitize failed issues during prepare', 0, async () => {
      const originalHooks = SharePhotoHelper.hooks
      try {
        class PrepareHooks implements SharePhotoHelperHooks {
          fileExists(path: string): boolean {
            return path === '/share/local-ok.jpg' || path === '/share/local-fail.jpg'
          }

          async sanitizeUpload(
            _ctx: common.UIAbilityContext,
            path: string
          ): Promise<string | undefined> {
            if (path === '/share/local-ok.jpg') {
              return '/share/sanitized-ok.jpg'
            }
            return undefined
          }

          deleteTemporary(_path: string): void {}
        }
        SharePhotoHelper.hooks = new PrepareHooks()

        const result = await SharePhotoHelper.prepareSharePhotos(createCtx(), 'node-1', [
          'users/demo/cloud.jpg',
          '/share/missing.jpg',
          '/share/local-fail.jpg',
          'file:///share/local-ok.jpg'
        ])

        expect(result.photos.length).assertEqual(1)
        expect(result.photos[0].filePath).assertEqual('/share/sanitized-ok.jpg')
        expect(result.issues.length).assertEqual(3)
        expect(result.issues[0].reason).assertEqual(SharePreflightErrorCode.CLOUD_ONLY_PHOTO)
        expect(result.issues[1].reason).assertEqual(SharePreflightErrorCode.LOCAL_PHOTO_MISSING)
        expect(result.issues[2].reason).assertEqual(SharePreflightErrorCode.PHOTO_SANITIZE_FAILED)
      } finally {
        SharePhotoHelper.hooks = originalHooks
      }
    })

    it('keeps sanitized jpeg outputs and cleanupPath during sanitize conversion', 0, async () => {
      const originalHooks = SharePhotoHelper.hooks
      try {
        class SanitizeHooks implements SharePhotoHelperHooks {
          fileExists(path: string): boolean {
            return path === '/share/source-a.png' || path === '/share/source-b.jpg'
          }

          async sanitizeUpload(
            _ctx: common.UIAbilityContext,
            path: string
          ): Promise<string | undefined> {
            if (path === '/share/source-a.png') {
              return '/share/sanitized-a.jpg'
            }
            if (path === '/share/source-b.jpg') {
              return '/share/sanitized-b.jpg'
            }
            return undefined
          }

          deleteTemporary(_path: string): void {}
        }
        SharePhotoHelper.hooks = new SanitizeHooks()

        const photos = await SharePhotoHelper.toSanitizedSharePhotos(createCtx(), [
          '/share/source-a.png',
          'file:///share/source-b.jpg',
          '/share/missing.jpg'
        ])

        expect(photos.length).assertEqual(2)
        expect(photos[0].filePath).assertEqual('/share/sanitized-a.jpg')
        expect(photos[0].filename).assertEqual('sanitized-a.jpg')
        expect(photos[0].contentType).assertEqual('image/jpeg')
        expect(photos[0].cleanupPath).assertEqual('/share/sanitized-a.jpg')
        expect(photos[1].filePath).assertEqual('/share/sanitized-b.jpg')
        expect(photos[1].cleanupPath).assertEqual('/share/sanitized-b.jpg')
      } finally {
        SharePhotoHelper.hooks = originalHooks
      }
    })

    it('cleans only photos carrying cleanupPath', 0, () => {
      const originalHooks = SharePhotoHelper.hooks
      const deleted: string[] = []
      try {
        class CleanupHooks implements SharePhotoHelperHooks {
          fileExists(_path: string): boolean {
            return false
          }

          async sanitizeUpload(
            _ctx: common.UIAbilityContext,
            _path: string
          ): Promise<string | undefined> {
            return undefined
          }

          deleteTemporary(path: string): void {
            deleted.push(path)
          }
        }
        SharePhotoHelper.hooks = new CleanupHooks()
        SharePhotoHelper.cleanupTemporaryPhotos(createTempPhotos())

        expect(deleted.length).assertEqual(2)
        expect(deleted[0]).assertEqual('/tmp/a.jpg')
        expect(deleted[1]).assertEqual('/tmp/c.jpg')
      } finally {
        SharePhotoHelper.hooks = originalHooks
      }
    })
  })
}
