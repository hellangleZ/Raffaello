# Testing Guide

## Quick Test (推荐)

运行自动化测试套件：

```bash
./run-tests.sh suite
```

这会测试所有改进和bug修复（~20个测试，耗时<10秒）。

## 预期输出

```
======================================
  Raffaello Test Suite
======================================

[TEST] Required files exist
  ✓ ralph.sh
  ✓ orchestrator.sh
  ...
  ✓ PASS All required files exist

[TEST] Bash 3.2 compatibility check
  ✓ PASS No associative arrays found

[TEST] Unified logging system integration
  ✓ ralph.sh uses unified logging
  ✓ orchestrator.sh uses unified logging
  ...
  ✓ PASS Unified logging integrated

...

======================================
  Test Results Summary
======================================
Total Tests:  20
Passed:       20
Failed:       0

✓ All tests passed!
```

## 手动测试步骤

如果想手动验证特定修复：

### 1. 测试PRD验证器

```bash
# 测试有效的PRD
./lib/prd-validator.sh prd.json.example

# 应该输出:
# ✓ PRD validation passed

# 测试无效的PRD
echo '{"invalid": true}' > test-bad.json
./lib/prd-validator.sh test-bad.json

# 应该报错:
# ERROR: Missing required field: projectName
# ERROR: Missing required field: branchName
# ...
```

### 2. 测试依赖分析器

```bash
# 分析依赖关系
./lib/dependency-analyzer.sh prd.json

# 应该输出JSON:
# {
#   "batches": [
#     ["US001", "US002"],
#     ["US003"]
#   ],
#   "unassigned": []
# }
```

### 3. 测试冲突分析器

```bash
# 测试常量配置
export CONFLICT_RATIO_HIGH_THRESHOLD=10
./lib/conflict-analyzer.sh

# 查看配置
grep THRESHOLD lib/conflict-analyzer.sh
```

### 4. 测试Bash 3.2兼容性

```bash
# 检查没有关联数组
grep -r "declare -A" *.sh lib/*.sh

# 应该没有输出（找不到）
```

### 5. 测试统一日志系统

```bash
# 查看logging.sh被正确引用
grep "source.*logging.sh" ralph.sh orchestrator.sh merge-stories.sh

# 应该输出3行
```

### 6. 测试临时文件清理

```bash
# 查看trap配置
grep "trap.*EXIT" orchestrator.sh ralph.sh

# 应该看到trap cleanup定义
```

## 完整集成测试

如果你想测试整个系统：

### 准备测试项目

```bash
cd test-project
git init
echo "# Test" > README.md
git add . && git commit -m "Initial commit"
```

### 创建测试PRD

```bash
cat > prd.json << 'EOF'
{
  "projectName": "Test Project",
  "branchName": "main",
  "userStories": [
    {
      "id": "US001",
      "title": "Add Hello World",
      "description": "Create a simple hello.txt file",
      "workflow": "simple",
      "dependencies": [],
      "passes": false
    },
    {
      "id": "US002",
      "title": "Add Goodbye",
      "description": "Create a goodbye.txt file",
      "workflow": "simple",
      "dependencies": ["US001"],
      "passes": false
    }
  ]
}
EOF
```

### 运行Ralph

```bash
# 确保在main分支
git checkout main

# 运行ralph（需要claude CLI）
./ralph.sh
```

### 验证结果

```bash
# 检查story分支被创建
git branch | grep story-

# 应该看到:
#   story-US001
#   story-US002

# 检查分支被合并
git log --oneline

# 应该看到US001和US002的commits

# 检查PRD更新
jq '.userStories[].passes' prd.json

# 应该都是true
```

## 性能测试

测试依赖分析器性能改进：

```bash
# 创建大型PRD（50个stories）
./scripts/generate-large-prd.sh 50 > large-prd.json

# 测试性能
time ./lib/dependency-analyzer.sh large-prd.json

# 新版应该比旧版快60%
```

## 回归测试

确保修复没有破坏现有功能：

```bash
# 1. 检查所有现有examples
for example in examples/*.json; do
  echo "Testing $example"
  ./lib/prd-validator.sh "$example"
done

# 2. 运行已有的测试
if [[ -f "tools/tests/test-workflows.sh" ]]; then
  ./run-tests.sh workflows
fi

# 3. 验证文档中的示例
grep -A 10 "```bash" README.md | \
  grep -v "```" | \
  grep -v "^--$" | \
  while read -r cmd; do
    echo "Testing: $cmd"
    eval "$cmd" || echo "Failed: $cmd"
  done
```

## 故障排查

如果测试失败：

### 测试失败：Prerequisites

```bash
# 安装缺失的工具
brew install jq yq

# 或使用包管理器
apt-get install jq yq  # Ubuntu
```

### 测试失败：Bash version

```bash
# 检查Bash版本
bash --version

# macOS升级Bash
brew install bash
```

### 测试失败：File not found

```bash
# 确保在项目根目录
cd /path/to/ralph-parallel

# 运行测试
./run-tests.sh suite
```

### 测试失败：Permission denied

```bash
# 添加执行权限
chmod +x tools/tests/test-improvements.sh
chmod +x ralph.sh orchestrator.sh merge-stories.sh
```

## CI/CD集成

可以在CI/CD管道中运行测试：

```yaml
# .github/workflows/test.yml
name: Test Improvements
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq yq
      - name: Run tests
        run: ./run-tests.sh suite
```

## 测试清单

运行完整测试前的检查清单：

- [ ] 在项目根目录
- [ ] 已安装 jq, yq, git
- [ ] tools/tests/test-improvements.sh 有执行权限
- [ ] 主要脚本有执行权限
- [ ] 有prd.json或prd.json.example

## 预期测试时间

- 快速测试套件: ~5-10秒
- 完整集成测试: ~2-5分钟（取决于story数量）
- 性能基准测试: ~1分钟

---

**建议**: 先运行 `./run-tests.sh suite` 快速验证所有修复，然后再进行手动测试或集成测试。
