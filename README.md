# Kotoha (ことは)

Kotoha is an on-device multilingual workspace. The first runnable interface is a
manual text-workspace draft: enter a source text, add one or more target languages,
and write translations without an installed model. It does not claim to translate
text automatically.

This development build does not yet save drafts. The product design requires saved
content to use encrypted storage and protected key management; persistence will be
added when its reviewed dependencies are available. Do not enter sensitive text in
this temporary build.

## Development

```sh
flutter test
flutter analyze
```

The generated native runners currently cover Android, iOS, macOS, and Windows.
Linux remains intentionally unscaffolded until its host can use the designed
non-GTK Flutter Engine embedding.
