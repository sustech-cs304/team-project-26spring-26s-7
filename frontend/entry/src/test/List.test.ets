import rdbHelperTest from './integration/data/RdbHelper.test';
import memoryNodeRepositoryTest from './integration/data/MemoryNodeRepository.test';
import travelRepositoryTest from './integration/data/TravelRepository.test';
import multipartFormDataTest from './unit/common/MultipartFormData.test';
import shareErrorMapperTest from './unit/social-share/ShareErrorMapper.test';
import sharePhotoHelperTest from './unit/social-share/SharePhotoHelper.test';
import sharePreflightTest from './unit/social-share/SharePreflight.test';
import shareServiceTest from './unit/social-share/ShareService.test';

export default function testsuite() {
  memoryNodeRepositoryTest();
  rdbHelperTest();
  multipartFormDataTest();
  shareErrorMapperTest();
  sharePhotoHelperTest();
  sharePreflightTest();
  shareServiceTest();
  travelRepositoryTest();
}
