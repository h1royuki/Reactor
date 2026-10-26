# Реактор — iOS-клиент для JoyReactor

Неофициальное нативное приложение для [joyreactor.cc](https://joyreactor.cc) на SwiftUI (iOS 17+).

## Возможности
- Лента с бесконечным скроллом: «Хорошее», «Лучшее», «Новое», «Все», «Обсуждаемое», «Топ недели»
- Картинки, анимированные GIF, видео (WebM), встраивания YouTube/Coub/Vimeo
- Полноэкранный просмотр с зумом и шарингом/сохранением
- Страницы тегов (подписка, блокировка, подтеги), пользователей
- Поиск по тегам и постам, тренды и популярные теги
- Пост с деревом комментариев (сворачивание веток, сортировка)
- Вход в аккаунт: голосование за посты и комментарии, избранное, опросы, комментарии
- Фильтр 18+ (выключен по умолчанию), тёмная тема, кэш медиа

## Сборка
Проект описан в `project.yml` ([XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```sh
brew install xcodegen
xcodegen generate
open Reactor.xcodeproj
```

GitHub Actions (`.github/workflows/build.yml`) собирает неподписанный `Reactor.ipa` на каждый пуш в `main`
и публикует его в Releases. Установить можно через AltStore, SideStore, Sideloadly или TrollStore.

Данные берутся из публичного GraphQL API `https://api.joyreactor.cc/graphql`.
