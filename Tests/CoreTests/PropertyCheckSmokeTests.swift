import Foundation
import PropertyBased
import Testing

/// Дымовая проверка оснастки: PropertyBased подключён к CoreTests и генератор действительно
/// доходит до тела проверки. Без неё сломанная зависимость всплыла бы только в первой PBT-задаче.
///
/// Модель Core здесь намеренно не трогается: её контракт принадлежит T1, а смоук обязан
/// оставаться зелёным при любых правках трека. Проверок ровно столько, сколько нужно, чтобы
/// генератор доказанно доходил до тела: свойства stdlib уже держат тесты Core.
@Test("PropertyBased подключён: propertyCheck гоняет генератор")
func propertyCheckSmoke() async {
    await propertyCheck(input: Gen.int(in: 1900...2099)) { year in
        // Год тега ходит через строку: колонка «Год» печатает число, разбор читает его обратно.
        #expect(Int(String(year)) == year)
        #expect(String(year).count == 4)
    }
}
