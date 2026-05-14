import { describe, it, expect } from '@ohos/hypium';
import { SharePreflight } from '../../../main/ets/feature/social-share/services/SharePreflight';
import {
  SharePreflightErrorCode,
  type SharePhotoIssue,
  type SharePublishNode,
  type SharePublishRequest
} from '../../../main/ets/feature/social-share/types/ShareTypes';
import type { SharePhoto } from '../../../main/ets/feature/social-share/services/ShareService';

function createRequest(nodeCount: number = 1, photoCount: number = 1): SharePublishRequest {
  const nodes: SharePublishNode[] = [];
  for (let i = 0; i < nodeCount; i++) {
    nodes.push({
      id: `node-${i}`,
      title: `Node ${i}`,
      content: `Content ${i}`,
      poiName: `POI ${i}`,
      photoCount,
      mood: 'calm',
      tags: ['tag'],
      visitedAt: 1715000000000 + i,
      nodeOrder: i
    });
  }
  return {
    tripId: 'trip-1',
    tripName: 'Trip',
    totalDistance: 12.5,
    coverIndex: 0,
    createdAt: 1715000000000,
    nodes
  };
}

function createPhotos(count: number): SharePhoto[] {
  const photos: SharePhoto[] = [];
  for (let i = 0; i < count; i++) {
    photos.push({
      filePath: `/share-tests/photo-${i}.jpg`,
      filename: `photo-${i}.jpg`,
      contentType: 'image/jpeg'
    });
  }
  return photos;
}

function createIssue(reason: string): SharePhotoIssue {
  return {
    nodeId: 'node-0',
    rawPath: 'users/demo/photo.jpg',
    reason,
    message: 'blocked'
  };
}

export default function sharePreflightTest() {
  describe('SharePreflightTest', () => {
    it('blocks empty node list', 0, () => {
      const req = createRequest(0, 1);
      const result = SharePreflight.validatePublish(req, [], 24);
      expect(result.ok).assertFalse();
      expect(result.errorCode).assertEqual('EMPTY_NODES');
    });

    it('blocks invalid expiry', 0, () => {
      const req = createRequest();
      const photos = createPhotos(1);
      const result = SharePreflight.validatePublish(req, photos, 0);
      expect(result.ok).assertFalse();
      expect(result.errorCode).assertEqual('INVALID_EXPIRY');
    });

    it('blocks mismatched photo count', 0, () => {
      const req = createRequest(1, 2);
      const photos = createPhotos(1);
      const result = SharePreflight.validatePublish(req, photos, 24);
      expect(result.ok).assertFalse();
      expect(result.errorCode).assertEqual('INVALID_PHOTO_COUNT');
    });

    it('blocks cloud only issue before size checks', 0, () => {
      const req = createRequest();
      const photos = createPhotos(1);
      const issues = [createIssue(SharePreflightErrorCode.CLOUD_ONLY_PHOTO)];
      const result = SharePreflight.validatePublish(req, photos, 24, issues);
      expect(result.ok).assertFalse();
      expect(result.errorCode).assertEqual(SharePreflightErrorCode.CLOUD_ONLY_PHOTO);
      expect(result.issues?.length ?? 0).assertEqual(1);
    });

    it('blocks missing local file issue', 0, () => {
      const req = createRequest();
      const photos = createPhotos(1);
      const issues = [createIssue(SharePreflightErrorCode.LOCAL_PHOTO_MISSING)];
      const result = SharePreflight.validatePublish(req, photos, 24, issues);
      expect(result.ok).assertFalse();
      expect(result.errorCode).assertEqual(SharePreflightErrorCode.LOCAL_PHOTO_MISSING);
    });

    it('passes valid publish payload', 0, () => {
      const req = createRequest(1, 0);
      const photos = createPhotos(0);
      const result = SharePreflight.validatePublish(req, photos, 24);
      expect(result.ok).assertTrue();
      expect(result.totalPhotoCount).assertEqual(0);
      expect((result.totalBytes ?? 0) > 0).assertTrue();
    });
  });
}
