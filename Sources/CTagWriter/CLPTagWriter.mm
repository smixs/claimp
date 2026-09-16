#import "CLPTagWriter.h"

#import <taglib/aifffile.h>
#import <taglib/fileref.h>
#import <taglib/id3v2header.h>
#import <taglib/id3v2tag.h>
#import <taglib/mpegfile.h>
#import <taglib/tfile.h>
#import <taglib/tpropertymap.h>
#import <taglib/wavfile.h>

#include <exception>

NSErrorDomain const CLPTagWriterErrorDomain = @"dev.shima.claimp.TagWriter";

namespace {

/// Ключи PropertyMap. Раскладку по контейнерам делает TagLib: ID3v2 TBPM/TKEY,
/// Vorbis comments BPM/INITIALKEY, MP4 tmpo и `----:com.apple.iTunes:INITIALKEY`.
const TagLib::String kBPMKey { "BPM" };
const TagLib::String kInitialKey { "INITIALKEY" };

BOOL fail(NSError **error, CLPTagWriterError code, NSString *reason) {
    if (error != nullptr) {
        *error = [NSError errorWithDomain:CLPTagWriterErrorDomain
                                     code:code
                                 userInfo:@{ NSLocalizedDescriptionKey: reason }];
    }
    return NO;
}

/// Заменяет значение одного ключа, не трогая остальную карту. nil - поле не меняется вовсе.
void replaceValue(TagLib::PropertyMap &properties, const TagLib::String &key, NSString *value) {
    if (value == nil) {
        return;
    }
    properties.replace(key, TagLib::StringList(TagLib::String(value.UTF8String, TagLib::String::UTF8)));
}

/// Версия ID3v2, которой перезаписать тег: та же, что уже лежит в файле. По умолчанию TagLib
/// пишет 2.4 и выбрасывает кадры, которых в 2.4 нет (TDAT), - то есть молча правит чужие теги.
TagLib::ID3v2::Version keptVersion(bool hasTag, const TagLib::ID3v2::Tag *tag) {
    if (hasTag && tag != nullptr && tag->header()->majorVersion() == 3) {
        return TagLib::ID3v2::v3;
    }
    return TagLib::ID3v2::v4;
}

/// Сохранение без смены версии ID3v2 там, где контейнер даёт её выбрать (MP3, WAV, AIFF).
/// У остальных (FLAC, MP4, Ogg) версий ID3v2 нет - им обычный save().
BOOL saveKeepingID3v2Version(TagLib::File *file) {
    if (auto *mpeg = dynamic_cast<TagLib::MPEG::File *>(file)) {
        return mpeg->save(TagLib::MPEG::File::AllTags, TagLib::File::StripOthers, keptVersion(mpeg->hasID3v2Tag(), mpeg->ID3v2Tag()));
    }
    if (auto *wav = dynamic_cast<TagLib::RIFF::WAV::File *>(file)) {
        return wav->save(TagLib::RIFF::WAV::File::AllTags, TagLib::File::StripOthers, keptVersion(wav->hasID3v2Tag(), wav->ID3v2Tag()));
    }
    if (auto *aiff = dynamic_cast<TagLib::RIFF::AIFF::File *>(file)) {
        return aiff->save(keptVersion(aiff->hasID3v2Tag(), aiff->tag()));
    }
    return file->save();
}

/// Ключ не принят контейнером: TagLib возвращает такие значения из setProperties.
BOOL wasIgnored(const TagLib::PropertyMap &ignored, const TagLib::String &key, NSString *value) {
    return value != nil && !ignored.value(key).isEmpty();
}

} // namespace

@implementation CLPTagWriter

+ (BOOL)writeBPM:(NSString *)bpm key:(NSString *)key toURL:(NSURL *)url error:(NSError **)error {
    NSParameterAssert(url != nil);
    if (bpm == nil && key == nil) {
        return YES;
    }
    try {
        // Аудиосвойства не читаем: для записи тега они не нужны, а на длинном MP3 это лишний проход.
        TagLib::FileRef ref(url.fileSystemRepresentation, false);
        if (ref.isNull()) {
            return fail(error, CLPTagWriterErrorUnsupportedFile,
                        @"file is missing or is not a supported audio container");
        }
        TagLib::File *file = ref.file();
        if (file->readOnly()) {
            return fail(error, CLPTagWriterErrorReadOnly, @"file is open for reading only");
        }
        // Карта читается целиком и возвращается целиком: меняются ровно два ключа,
        // остальные теги файла записываются своими же значениями.
        TagLib::PropertyMap properties = file->properties();
        replaceValue(properties, kBPMKey, bpm);
        replaceValue(properties, kInitialKey, key);
        const TagLib::PropertyMap ignored = file->setProperties(properties);
        if (wasIgnored(ignored, kBPMKey, bpm) || wasIgnored(ignored, kInitialKey, key)) {
            return fail(error, CLPTagWriterErrorUnsupportedField,
                        @"container does not support tempo or key tags");
        }
        if (!saveKeepingID3v2Version(file)) {
            return fail(error, CLPTagWriterErrorSaveFailed, @"TagLib refused to save the file");
        }
        return YES;
    } catch (const std::exception &failure) {
        return fail(error, CLPTagWriterErrorSaveFailed, @(failure.what()));
    } catch (...) {
        return fail(error, CLPTagWriterErrorSaveFailed, @"TagLib failed with an unknown error");
    }
}

@end
