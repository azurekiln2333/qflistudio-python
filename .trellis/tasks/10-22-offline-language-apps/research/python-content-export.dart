import 'dart:convert';
import 'dart:io';

import 'file:///D:/MyNewProjects/qfli_studio_core/tool/python_content/python_topics.dart';

void main(List<String> args) {
  File(args.single).writeAsStringSync(jsonEncode([
    for (final t in pythonTopics)
      {
        'id': t.id,
        'tutorialId': t.tutorialId,
        'exampleId': t.exampleId,
        'title': t.title,
        'code': t.code,
        'output': t.output,
        'objective': t.objective,
        'explain': t.explain,
        'prerequisites': t.prerequisites,
        'pitfalls': t.pitfalls,
        'input': t.input,
        'runtime': t.isEmbedded ? 'embedded' : 'cpython',
        'tasks': [
          for (final task in t.tasks)
            {'prompt': task.prompt, 'hint': task.hint, 'answer': task.answer},
        ],
      },
  ]));
  stdout.writeln('Exported ${pythonTopics.length} authored topics.');
}
