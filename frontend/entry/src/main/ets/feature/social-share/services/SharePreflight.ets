import { fileIo as fs } from '@kit.CoreFileKit'
import { SharePhoto } from './ShareService'
import {
  SharePhotoIssue,
  SharePreflightErrorCode,
  SharePreflightResult,
  SharePublishRequest,
} from '../types/ShareTypes'

const MAX_NODES = 30
const MAX_PHOTO_BYTES = 20 * 1024 * 1024
const MAX_BODY_BYTES = 100 * 1024 * 1024
const MIN_EXPIRY_HOURS = 1
const MAX_EXPIRY_HOURS = 720
const MULTIPART_OVERHEAD_PER_FILE = 1024

export class SharePreflight {
  static validatePublish(
    req: SharePublishRequest,
    photos: SharePhoto[],
    expiryHours: number,
    issues: SharePhotoIssue[] = []
  ): SharePreflightResult {
    const blockedByIssue = SharePreflight.validateIssues(issues, photos)
    if (blockedByIssue) {
      return blockedByIssue
    }

    if (req.nodes.length === 0) {
      return SharePreflight.fail('EMPTY_NODES', 'No shareable nodes found', 0, 0)
    }

    if (req.nodes.length > MAX_NODES) {
      return SharePreflight.fail(
        'TOO_MANY_NODES',
        `Node count exceeds limit (${MAX_NODES})`,
        photos.length,
        0
      )
    }

    if (expiryHours < MIN_EXPIRY_HOURS || expiryHours > MAX_EXPIRY_HOURS) {
      return SharePreflight.fail(
        'INVALID_EXPIRY',
        `Expiry must be between ${MIN_EXPIRY_HOURS} and ${MAX_EXPIRY_HOURS} hours`,
        photos.length,
        0
      )
    }

    let expectedTotal = 0
    for (let i = 0; i < req.nodes.length; i++) {
      expectedTotal += req.nodes[i].photoCount
    }
    if (expectedTotal !== photos.length) {
      return SharePreflight.fail(
        'INVALID_PHOTO_COUNT',
        'Photo count does not match node photoCount sum',
        photos.length,
        0
      )
    }

    let totalBytes = 0
    for (let i = 0; i < photos.length; i++) {
      const bytes = SharePreflight.statBytes(photos[i].filePath)
      totalBytes += bytes
      if (bytes > MAX_PHOTO_BYTES) {
        return SharePreflight.fail(
          'PHOTO_TOO_LARGE',
          'At least one photo exceeds the 20 MB limit',
          photos.length,
          totalBytes
        )
      }
    }

    const estimatedBodyBytes =
      totalBytes + JSON.stringify(req).length + expiryHours.toString().length +
      (photos.length + 2) * MULTIPART_OVERHEAD_PER_FILE

    if (estimatedBodyBytes > MAX_BODY_BYTES) {
      return SharePreflight.fail(
        'BODY_TOO_LARGE',
        'Share payload is too large. Reduce photos or nodes and try again.',
        photos.length,
        estimatedBodyBytes
      )
    }

    return {
      ok: true,
      totalPhotoCount: photos.length,
      totalBytes: estimatedBodyBytes,
      issues,
    }
  }

  private static validateIssues(
    issues: SharePhotoIssue[],
    photos: SharePhoto[]
  ): SharePreflightResult | undefined {
    if (issues.length === 0) {
      return undefined
    }

    const cloudOnlyCount = issues.filter(
      (item: SharePhotoIssue) => item.reason === SharePreflightErrorCode.CLOUD_ONLY_PHOTO
    ).length
    if (cloudOnlyCount > 0) {
      return SharePreflight.fail(
        SharePreflightErrorCode.CLOUD_ONLY_PHOTO,
        'This route includes cloud-only photos and cannot be shared completely on this device.',
        photos.length,
        0,
        `${cloudOnlyCount} cloud-only photos need a local recovery step before sharing.`,
        issues
      )
    }

    const missingCount = issues.filter(
      (item: SharePhotoIssue) => item.reason === SharePreflightErrorCode.LOCAL_PHOTO_MISSING
    ).length
    if (missingCount > 0) {
      return SharePreflight.fail(
        SharePreflightErrorCode.LOCAL_PHOTO_MISSING,
        'Some local photo files are missing, so the route cannot be shared completely.',
        photos.length,
        0,
        `${missingCount} photo files could not be found on this device.`,
        issues
      )
    }

    const sanitizeCount = issues.filter(
      (item: SharePhotoIssue) => item.reason === SharePreflightErrorCode.PHOTO_SANITIZE_FAILED
    ).length
    if (sanitizeCount > 0) {
      return SharePreflight.fail(
        SharePreflightErrorCode.PHOTO_SANITIZE_FAILED,
        'Some photos failed EXIF sanitization before sharing.',
        photos.length,
        0,
        `${sanitizeCount} photos failed sanitization and blocked publish.`,
        issues
      )
    }

    return undefined
  }

  private static statBytes(filePath: string): number {
    try {
      return fs.statSync(filePath).size
    } catch (_) {
      return MAX_PHOTO_BYTES + 1
    }
  }

  private static fail(
    errorCode: string,
    message: string,
    totalPhotoCount: number,
    totalBytes: number,
    detail?: string,
    issues?: SharePhotoIssue[]
  ): SharePreflightResult {
    return {
      ok: false,
      errorCode,
      message,
      detail,
      totalPhotoCount,
      totalBytes,
      issues,
    }
  }
}
