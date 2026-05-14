import { describe, it, expect } from '@ohos/hypium';
import { MultipartFormData } from '../../../main/ets/common/api/MultipartFormData';

export default function multipartFormDataTest() {
  describe('MultipartFormDataTest', () => {
    it('includes boundary in content type', 0, () => {
      const form = new MultipartFormData();
      const contentType = form.getContentType();
      expect(contentType).assertContain('multipart/form-data; boundary=');
    });

    it('builds multipart payload for text fields only', 0, async () => {
      const form = new MultipartFormData();
      form.addField('tripData', '{"tripId":"1"}');
      form.addField('expiryHours', '24');

      const payload = await form.build();

      expect(payload !== undefined).assertTrue();
    });
  });
}
