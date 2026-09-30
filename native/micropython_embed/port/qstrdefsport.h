/*
 * Port 私有的 qstr 定义。
 *
 * MicroPython 生成 qstr 表时会把三个文件拼起来预处理：
 *     py/qstrdefs.h  +  本文件  +  扫描源码收集到的 Q(...)
 * 本文件就是给 port 手工塞额外 qstr 的地方，比如「源码里扫不到、但运行时
 * 要按名字查」的字符串。
 *
 * native/src/ 不参与上游 qstr 扫描，所以文件对象独有的名字要放在这里。
 */
Q(mode)
Q(r)
Q(readlines)
