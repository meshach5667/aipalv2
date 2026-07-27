import 'dart:html' as html;

void setWebPageTitleImpl(String title) {
  try {
    html.document.title = title;
  } catch (_) {}
}
