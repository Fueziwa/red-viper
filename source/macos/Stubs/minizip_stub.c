//
//  minizip_stub.c
//  Red Viper - Stub implementations for minizip API
//
//  These stubs return errors to indicate that minizip is not available.
//  The macOS port will use libarchive for ZIP file handling instead.
//

#include "minizip/unzip.h"
#include <stddef.h>

// All functions return error values or NULL to indicate unavailability

unzFile unzOpen(const char *path) {
    (void)path;
    return NULL;  // NULL indicates failure to open
}

int unzClose(unzFile file) {
    (void)file;
    return UNZ_PARAMERROR;
}

int unzGoToFirstFile(unzFile file) {
    (void)file;
    return UNZ_PARAMERROR;
}

int unzGoToNextFile(unzFile file) {
    (void)file;
    return UNZ_END_OF_LIST_OF_FILE;
}

int unzGetCurrentFileInfo(unzFile file, unz_file_info *pfile_info,
                          char *szFileName, unsigned long fileNameBufferSize,
                          void *extraField, unsigned long extraFieldBufferSize,
                          char *szComment, unsigned long commentBufferSize) {
    (void)file;
    (void)pfile_info;
    (void)szFileName;
    (void)fileNameBufferSize;
    (void)extraField;
    (void)extraFieldBufferSize;
    (void)szComment;
    (void)commentBufferSize;
    return UNZ_PARAMERROR;
}

int unzOpenCurrentFile(unzFile file) {
    (void)file;
    return UNZ_PARAMERROR;
}

int unzCloseCurrentFile(unzFile file) {
    (void)file;
    return UNZ_PARAMERROR;
}

int unzReadCurrentFile(unzFile file, void *buf, unsigned len) {
    (void)file;
    (void)buf;
    (void)len;
    return UNZ_PARAMERROR;
}
