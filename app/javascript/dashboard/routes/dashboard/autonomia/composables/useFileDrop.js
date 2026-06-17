import { ref } from 'vue';

// Drag-and-drop helper for the Materiais step (and the Knowledge tab). Tracks a
// reactive `isDragging` flag and returns a `bind` object of native handlers to
// spread onto the dropzone container. Files are validated by extension against
// `accept` (default: the formats the backend ingests) and emitted via the
// `onFiles` callback. Invalid files are dropped silently here — the caller owns
// any user-facing messaging.
const DEFAULT_ACCEPTED = ['pdf', 'docx', 'xlsx', 'txt', 'md', 'json'];

const extensionOf = name => (name || '').split('.').pop()?.toLowerCase() || '';

export function useFileDrop(onFiles, accept = DEFAULT_ACCEPTED) {
  const isDragging = ref(false);
  // Depth counter so nested children entering/leaving don't flip the flag off
  // while the pointer is still over the dropzone.
  let depth = 0;

  const filterValid = fileList => {
    const files = Array.from(fileList || []);
    return files.filter(file => accept.includes(extensionOf(file.name)));
  };

  const onDragEnter = event => {
    event.preventDefault();
    depth += 1;
    isDragging.value = true;
  };

  const onDragOver = event => {
    event.preventDefault();
    isDragging.value = true;
  };

  const onDragLeave = event => {
    event.preventDefault();
    depth = Math.max(0, depth - 1);
    if (depth === 0) isDragging.value = false;
  };

  const onDrop = event => {
    event.preventDefault();
    depth = 0;
    isDragging.value = false;
    const valid = filterValid(event.dataTransfer?.files);
    if (valid.length) onFiles(valid);
  };

  const bind = {
    onDragenter: onDragEnter,
    onDragover: onDragOver,
    onDragleave: onDragLeave,
    onDrop,
  };

  return { isDragging, bind, filterValid };
}
