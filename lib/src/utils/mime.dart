/// MIME-type helpers used by multipart uploads.
///
/// The JavaScript SDK gets a `Blob`'s `type` for free from the browser. Dart
/// has no equivalent, so the SDK infers a type from the filename extension —
/// with an explicit override always available on the upload call.
library;

import 'package:http_parser/http_parser.dart';

/// Extension-to-MIME mappings covering the formats a mobile or web app
/// realistically uploads.
///
/// Anything not listed falls back to `application/octet-stream`, which every
/// storage provider accepts; pass an explicit content type when uploading an
/// unusual format that the provider needs to recognise.
const Map<String, String> _mimeTypes = <String, String>{
  // Images
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'svg': 'image/svg+xml',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'avif': 'image/avif',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'ico': 'image/x-icon',
  // Video
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mov': 'video/quicktime',
  'avi': 'video/x-msvideo',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  // Audio
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'flac': 'audio/flac',
  'opus': 'audio/opus',
  // Documents
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'rtf': 'application/rtf',
  // Text and data
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'tsv': 'text/tab-separated-values',
  'html': 'text/html',
  'htm': 'text/html',
  'css': 'text/css',
  'js': 'text/javascript',
  'json': 'application/json',
  'xml': 'application/xml',
  'yaml': 'application/yaml',
  'yml': 'application/yaml',
  // Archives
  'zip': 'application/zip',
  'gz': 'application/gzip',
  'tar': 'application/x-tar',
  'rar': 'application/vnd.rar',
  '7z': 'application/x-7z-compressed',
  // Fonts
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
};

/// The default type for content whose format cannot be determined.
const String defaultMimeType = 'application/octet-stream';

/// Infers a MIME type from [filename]'s extension.
///
/// Returns [defaultMimeType] when the extension is missing or unrecognised.
///
/// ```dart
/// inferMimeType('photo.HEIC'); // => 'image/heic'
/// inferMimeType('archive.bin'); // => 'application/octet-stream'
/// ```
String inferMimeType(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return defaultMimeType;
  final extension = filename.substring(dot + 1).toLowerCase();
  return _mimeTypes[extension] ?? defaultMimeType;
}

/// Parses [value] into a [MediaType] for a multipart part header.
///
/// Falls back to [defaultMimeType] if [value] is not a well-formed media type,
/// so a malformed caller-supplied string can never throw mid-upload.
MediaType parseMediaType(String value) {
  try {
    return MediaType.parse(value);
  } on Object {
    return MediaType.parse(defaultMimeType);
  }
}
