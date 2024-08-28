# 2024lab1-构造词法分析器
For 2024Fall NKUCS Course - Principle of Compilers Lab1

> Original Author: Emanual20 YoungCoder
> 
> Date: 2024/9/5

## 编译器命令
```
Usage：build/compiler [options] infile
Options:
    -o <file>   Place the output into <file>.
    -t          Print tokens.
```

## Makefile使用

* 修改测试路径：

默认测试路径为test，你可以修改为任意要测试的路径。我们已将最终所有测试样例分级上传。

如：要测试level1-1下所有sy文件，可以将makefile中的

```
TEST_PATH ?= test
```

修改为

```
TEST_PATH ?= test/level1-1
```

* 编译：

```
    make
```
编译出我们的编译器。

* 运行：
```
    make run
```
以example.sy文件为输入，输出相应的词法分析结果到example.toks文件中。

* 测试：
```
    make test
```
该命令会默认搜索test目录下所有的.sy文件，逐个输入到编译器中，生成相应的词法分析结果.toks文件到test目录中。你还可以指定测试目录：
```
    make test TEST_PATH=dirpath
```

* 清理:
```
    make clean
```
清除所有可执行文件和测试输出。
