SHELL:=/bin/bash
SRC_PATH ?= src
INC_PATH += include
BUILD_PATH ?= build
TEST_PATH ?= test
OBJ_PATH ?= $(BUILD_PATH)/obj
BINARY ?= $(BUILD_PATH)/compiler
SYSLIB_PATH ?= sysyruntimelibrary

INC = $(addprefix -I, $(INC_PATH))
SRC = $(shell find $(SRC_PATH)  -name "*.cpp")
CFLAGS = -O2 -g -Wall -Werror $(INC)
FLEX ?= $(SRC_PATH)/lexer.l
LEXER ?= $(addsuffix .cpp, $(basename $(FLEX)))
BISON ?= $(SRC_PATH)/parser.y
PARSER ?= $(addsuffix .cpp, $(basename $(BISON)))
SRC += $(LEXER)
SRC += $(PARSER)
OBJ = $(SRC:$(SRC_PATH)/%.cpp=$(OBJ_PATH)/%.o)
PARSERH ?= $(INC_PATH)/$(addsuffix .h, $(notdir $(basename $(PARSER))))

TESTCASE = $(shell find $(TEST_PATH) -name "*.sy")
TESTCASE_NUM = $(words $(TESTCASE))
LLVM_IR = $(addsuffix _std.ll, $(basename $(TESTCASE)))
OUTPUT_LAB1 = $(addsuffix .toks, $(basename $(TESTCASE)))
OUTPUT_LAB2 = $(addsuffix .ast, $(basename $(TESTCASE)))
OUTPUT_LAB3 = $(addsuffix .ll, $(basename $(TESTCASE)))
OUTPUT_RES = $(addsuffix .res, $(basename $(TESTCASE)))
OUTPUT_BIN = $(addsuffix .bin, $(basename $(TESTCASE)))
OUTPUT_LOG = $(addsuffix .log, $(basename $(TESTCASE)))

.phony:all app run gdb testlab1 testlab2 testlab3 test check_mem2reg check_unreachable clean clean-all clean-test clean-app llvmir

all:app

$(LEXER):$(FLEX)
	@flex -o $@ $<

$(PARSER):$(BISON)
	@bison -o $@ $< --warnings=error=all --defines=$(PARSERH)

$(OBJ_PATH)/%.o:$(SRC_PATH)/%.cpp
	@mkdir -p $(OBJ_PATH)
	@g++ $(CFLAGS) -c -o $@ $<

$(BINARY):$(OBJ)
	@g++ -O2 -g -o $@ $^

app:$(LEXER) $(PARSER) $(BINARY)

run:app
	@$(BINARY) -o example.ll -i example.sy

gdb:app
	@gdb $(BINARY)

$(OBJ_PATH)/lexer.o:$(SRC_PATH)/lexer.cpp
	@mkdir -p $(OBJ_PATH)
	@g++ $(CFLAGS) -c -o $@ $<

$(TEST_PATH)/%.toks:$(TEST_PATH)/%.sy
	@$(BINARY) $< -o $@ -t

$(TEST_PATH)/%.ast:$(TEST_PATH)/%.sy
	@$(BINARY) $< -o $@ -a

$(TEST_PATH)/%.ll:$(TEST_PATH)/%.sy
	@timeout 5s $(BINARY) $< -o $@ -i 2>$(addsuffix .log, $(basename $@))
	@[ $$? != 0 ] && echo -e "\033[1;31mFAIL:\033[0m $(notdir $<)" || echo -e "\033[1;32mSUCCESS:\033[0m $(notdir $<)"

$(TEST_PATH)/%_std.ll:$(TEST_PATH)/%.sy
	@clang -x c $< -S -m32 -emit-llvm -o $@ 

llvmir:$(LLVM_IR)

testlab1:app $(OUTPUT_LAB1)

testlab2:app $(OUTPUT_LAB2)

testlab3:app $(OUTPUT_LAB3)

.ONESHELL:
test:app
	@success=0
	@for file in $(sort $(TESTCASE))
	do
		IR=$${file%.*}.ll
		LOG=$${file%.*}.log
		BIN=$${file%.*}.bin
		RES=$${file%.*}.res
		IN=$${file%.*}.in
		OUT=$${file%.*}.out
		FILE=$${file##*/}
		FILE=$${FILE%.*}
		timeout 60s $(BINARY) $${file} -o $${IR} -i 2>$${LOG}
		RETURN_VALUE=$$?
		if [ $$RETURN_VALUE = 124 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Timeout\033[0m"
			continue
		else if [ $$RETURN_VALUE != 0 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Error\033[0m"
			continue
			fi
		fi
		clang -o $${BIN} $${IR} $(SYSLIB_PATH)/sylib.c >>$${LOG} 2>&1
		if [ $$? != 0 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mAssemble Error\033[0m"
		else
			if [ -f "$${IN}" ]; then
				timeout 10s $${BIN} <$${IN} >$${RES} 2>>$${LOG}
			else
				timeout 10s $${BIN} >$${RES} 2>>$${LOG}
			fi
			RETURN_VALUE=$$?
			
			FINAL=`tail -c 1 $${RES}`
			@LAST_CHAR=`tail -c 1 "$${RES}" | od -An -t u1 | tr -d ' \n'` ; \
			if [ "$${LAST_CHAR}" != "10" ] && [ "$${LAST_CHAR}" != "" ]; then \
    			echo "" >> "$${RES}" ; \
			fi
			echo "$${RETURN_VALUE}" >> "$${RES}"
			
			
			if [ "$${RETURN_VALUE}" = "124" ]; then
				echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Timeout\033[0m"
			else if [ "$${RETURN_VALUE}" = "127" ]; then
				echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Error\033[0m"
				else
					diff -Z $${RES} $${OUT} >/dev/null 2>&1
					if [ $$? != 0 ]; then
						echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mWrong Answer\033[0m"
					else
						success=$$((success + 1))
						echo -e "\033[1;32mPASS:\033[0m $${FILE}"
					fi
				fi
			fi
		fi
	done
	echo -e "\033[1;33mTotal: $(TESTCASE_NUM)\t\033[1;32mAccept: $${success}\t\033[1;31mFail: $$(($(TESTCASE_NUM) - $${success}))\033[0m"
	[ $(TESTCASE_NUM) = $${success} ] && echo -e "\033[5;32mAll Accepted. Congratulations!\033[0m"
	:

check_mem2reg:
	@total_files=0
	@passed_files=0
	OPTIMIZE_DIR=test/optimize_test/basic_mem2reg/
	for file in $$(find $${OPTIMIZE_DIR} -name "*.sy")
	do
		IR=$${file%.*}.ll
		LOG=$${file%.*}.log
		BIN=$${file%.*}.bin
		RES=$${file%.*}.res
		IN=$${file%.*}.in
		OUT=$${file%.*}.out
		FILE=$${file##*/}
		FILE=$${FILE%.*}
		timeout 60s $(BINARY) $${file} -o $${IR} -i 2>$${LOG}
		RETURN_VALUE=$$?
		total_files=$$((total_files + 1))
	
		if [ $$RETURN_VALUE = 124 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Timeout\033[0m"
			continue
		else if [ $$RETURN_VALUE != 0 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Error\033[0m"
			continue
			fi
		fi
		
		clang -o $${BIN} $${IR} $(SYSLIB_PATH)/sylib.c >>$${LOG} 2>&1
		if [ $$? != 0 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mAssemble Error\033[0m"
			continue
		else
			if [ -f "$${IN}" ]; then
				timeout 10s $${BIN} <$${IN} >$${RES} 2>>$${LOG}
			else
				timeout 10s $${BIN} >$${RES} 2>>$${LOG}
			fi
			RETURN_VALUE=$$?
			FINAL=`tail -c 1 $${RES}`
			[ $${FINAL} ] && echo -e "\n$${RETURN_VALUE}" >> $${RES} || echo "$${RETURN_VALUE}" >> $${RES}
			if [ "$${RETURN_VALUE}" = "124" ]; then
				echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Timeout\033[0m"
				continue
			else if [ "$${RETURN_VALUE}" = "127" ]; then
				echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Error\033[0m"
				continue
				else
					diff -Z $${RES} $${OUT} >/dev/null 2>&1
					if [ $$? != 0 ]; then
						echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mWrong Answer\033[0m"
						continue
					else
						echo -e "\033[1;32mCorrect Answer:\033[0m $${FILE}"
					fi
				fi
			fi
		fi
		
		
		if ! grep -q "alloca" $${IR}; then
			passed_files=$$((passed_files + 1)) 
			echo -e "\033[1;32mPASS:\033[0m $${FILE}"
		else
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mContains 'alloca'\033[0m"
		fi
	done
	if [ $${total_files} -gt 0 ]; then
		echo -e "\033[1;33mTotal .ll files: $${total_files}\tPassed: $${passed_files}\tFailed: $$(($${total_files} - $${passed_files}))\033[0m"
	else
		echo -e "\033[1;31mNo .ll files found in $${OPTIMIZE_DIR}\033[0m"
	fi

check_unreachable:
	@total_files=0
	@passed_files=0
	OPTIMIZE_DIR=test/optimize_test/eliUnreachablebb/
	@if [ ! -d "$${OPTIMIZE_DIR}" ]; then \
		echo -e "\033[1;31mDirectory $${OPTIMIZE_DIR} does not exist.\033[0m"; \
		exit 1; \
	fi
	@for file in $$(find $${OPTIMIZE_DIR} -name "*.sy")
	do \
		IR=$${file%.*}.ll
		LOG=$${file%.*}.log
		BIN=$${file%.*}.bin
		RES=$${file%.*}.res
		IN=$${file%.*}.in
		OUT=$${file%.*}.out
		FILE=$${file##*/}
		FILE=$${FILE%.*}
		timeout 60s $(BINARY) $${file} -o $${IR} -i 2>$${LOG}
		RETURN_VALUE=$$?
		total_files=$$((total_files + 1))
		if [ $$RETURN_VALUE = 124 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Timeout\033[0m"
			continue
		else if [ $$RETURN_VALUE != 0 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mCompile Error\033[0m"
			continue
			fi
		fi
		
		clang -o $${BIN} $${IR} $(SYSLIB_PATH)/sylib.c >>$${LOG} 2>&1
		if [ $$? != 0 ]; then
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mAssemble Error\033[0m"
			continue
		else
			if [ -f "$${IN}" ]; then
				timeout 10s $${BIN} <$${IN} >$${RES} 2>>$${LOG}
			else
				timeout 10s $${BIN} >$${RES} 2>>$${LOG}
			fi
			RETURN_VALUE=$$?
			FINAL=`tail -c 1 $${RES}`
			[ $${FINAL} ] && echo -e "\n$${RETURN_VALUE}" >> $${RES} || echo "$${RETURN_VALUE}" >> $${RES}
			if [ "$${RETURN_VALUE}" = "124" ]; then
				echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Timeout\033[0m"
				continue
			else if [ "$${RETURN_VALUE}" = "127" ]; then
				echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mExecute Error\033[0m"
				continue
				else
					diff -Z $${RES} $${OUT} >/dev/null 2>&1
					if [ $$? != 0 ]; then
						echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mWrong Answer\033[0m"
						continue
					else
						echo -e "\033[1;32mCorrect Answer:\033[0m $${FILE}"
					fi
				fi
			fi
		fi
		
		file_size=$$(stat -c %s $${IR}); \
		if [ $${file_size} -lt 8000 ]; then \
			passed_files=$$((passed_files + 1)); \
			echo -e "\033[1;32mPASS:\033[0m $${FILE}\t\033[1;32mFile size: $${file_size} bytes\033[0m"; \
		else \
			echo -e "\033[1;31mFAIL:\033[0m $${FILE}\t\033[1;31mFile size: $${file_size} bytes (greater than or equal to 8000 bytes)\033[0m"; \
		fi; \
	done
	
	@if [ $${total_files} -gt 0 ]; then \
		echo -e "\033[1;33mTotal .ll files: $${total_files}\tPassed: $${passed_files}\tFailed: $$(($${total_files} - $${passed_files}))\033[0m"; \
	else \
		echo -e "\033[1;31mNo .ll files found in $${OPTIMIZE_DIR}\033[0m"; \
	fi


clean-app:
	@rm -rf $(BUILD_PATH) $(PARSER) $(LEXER) $(PARSERH)

clean-test:
	@rm -rf $(OUTPUT_LAB1) $(OUTPUT_LAB2) $(OUTPUT_LAB3) $(OUTPUT_LOG) $(OUTPUT_BIN) $(OUTPUT_RES) $(LLVM_IR) *.toks *.ast *.ll *.s *.out

clean-all:clean-test clean-app

clean:clean-all
