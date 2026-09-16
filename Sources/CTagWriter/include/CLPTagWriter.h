#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Домен ошибок записи тегов. Причина лежит в NSLocalizedDescriptionKey.
extern NSErrorDomain const CLPTagWriterErrorDomain;

typedef NS_ERROR_ENUM(CLPTagWriterErrorDomain, CLPTagWriterError){
    /// Файла нет, он не аудио или контейнер не распознан.
    CLPTagWriterErrorUnsupportedFile = 1,
    /// Файл открылся только на чтение (права, том только для чтения).
    CLPTagWriterErrorReadOnly = 2,
    /// Контейнер не умеет хранить темп или тональность.
    CLPTagWriterErrorUnsupportedField = 3,
    /// TagLib не смог записать файл.
    CLPTagWriterErrorSaveFailed = 4,
};

/// Запись темпа и тональности в теги аудиофайла средствами TagLib.
///
/// Значения приходят готовыми строками: округление темпа и выбор записи тональности -
/// дело Swift-слоя, здесь только контейнеры. nil-поле не трогается, остальные теги файла
/// переписываются своими же значениями.
@interface CLPTagWriter : NSObject

+ (BOOL)writeBPM:(nullable NSString *)bpm
             key:(nullable NSString *)key
           toURL:(NSURL *)url
           error:(NSError **)error NS_SWIFT_NAME(write(bpm:key:to:));

@end

NS_ASSUME_NONNULL_END
