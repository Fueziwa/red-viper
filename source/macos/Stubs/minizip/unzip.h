//
//  unzip.h
//  Red Viper - Stub header for minizip compatibility
//
//  The original C core uses minizip for ZIP file handling.
//  On macOS, we use libarchive instead, but we need stub definitions
//  to satisfy the compiler.
//

#ifndef MINIZIP_UNZIP_H
#define MINIZIP_UNZIP_H

#include <stddef.h>

// Minizip error codes
#define UNZ_OK                  0
#define UNZ_END_OF_LIST_OF_FILE (-100)
#define UNZ_ERRNO               (-1)
#define UNZ_EOF                 (-1)
#define UNZ_PARAMERROR          (-102)
#define UNZ_BADZIPFILE          (-103)
#define UNZ_INTERNALERROR       (-104)
#define UNZ_CRCERROR            (-105)

// Opaque handle type
typedef void* unzFile;

// File info structure
typedef struct unz_file_info_s {
    unsigned long version;
    unsigned long version_needed;
    unsigned long flag;
    unsigned long compression_method;
    unsigned long dosDate;
    unsigned long crc;
    unsigned long compressed_size;
    unsigned long uncompressed_size;
    unsigned long size_filename;
    unsigned long size_file_extra;
    unsigned long size_file_comment;
    unsigned long disk_num_start;
    unsigned long internal_fa;
    unsigned long external_fa;
} unz_file_info;

// Function declarations (stub implementations)
unzFile unzOpen(const char *path);
int unzClose(unzFile file);
int unzGoToFirstFile(unzFile file);
int unzGoToNextFile(unzFile file);
int unzGetCurrentFileInfo(unzFile file, unz_file_info *pfile_info,
                          char *szFileName, unsigned long fileNameBufferSize,
                          void *extraField, unsigned long extraFieldBufferSize,
                          char *szComment, unsigned long commentBufferSize);
int unzOpenCurrentFile(unzFile file);
int unzCloseCurrentFile(unzFile file);
int unzReadCurrentFile(unzFile file, void *buf, unsigned len);

#endif // MINIZIP_UNZIP_H
