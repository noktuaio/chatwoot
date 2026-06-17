/* global axios */
import ApiClient from '../ApiClient';

// Builder image uploads (multimodal). The Construtor/Ajustar conversation is
// ASYNCHRONOUS (the build runs in a job), so an image cannot ride inline like in
// the synchronous Test path. Instead it is uploaded to ActiveStorage here and
// referenced by `signed_id` on the message turn; the Builder resolves the blob
// in the job and reads it inline (input_image).
//
// CONTRACT (AREA-BE): POST autonomia/builder_images (multipart `file`) →
// { signed_id, content_type }. The endpoint validates IMAGE content-types and
// size only; it never creates a knowledge Source.
class AutonomiaBuilderImagesAPI extends ApiClient {
  constructor() {
    super('autonomia/builder_images', { accountScoped: true });
  }

  upload(file) {
    const formData = new FormData();
    formData.append('file', file);
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new AutonomiaBuilderImagesAPI();
