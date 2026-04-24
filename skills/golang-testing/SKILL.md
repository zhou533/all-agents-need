---
name: golang-testing
description: Go 测试模式，涵盖表驱动测试、子测试、基准测试、模糊测试与测试覆盖率；遵循 TDD 方法论与地道 Go 实践。
origin: AAN
---

# Go 测试模式

一套完整的 Go 测试模式，用于在 TDD 方法论下编写可靠、可维护的测试。

## 何时激活

- 编写新的 Go 函数或方法
- 为既有代码补充测试覆盖
- 为性能关键路径编写基准测试
- 为输入校验编写模糊测试
- 在 Go 项目中执行 TDD 流程

## Go 的 TDD 流程

### RED-GREEN-REFACTOR 循环

```
RED      → 先写一个失败的测试
GREEN    → 写最少的代码让测试通过
REFACTOR → 在保持测试绿色的前提下改进代码
REPEAT   → 继续下一条需求
```

### Go 中 TDD 的分步示例

```go
// Step 1: 先定义接口 / 签名
// calculator.go
package calculator

func Add(a, b int) int {
    panic("not implemented") // 占位
}

// Step 2: 写失败的测试（RED）
// calculator_test.go
package calculator

import "testing"

func TestAdd(t *testing.T) {
    got := Add(2, 3)
    want := 5
    if got != want {
        t.Errorf("Add(2, 3) = %d; want %d", got, want)
    }
}

// Step 3: 运行测试 —— 确认 FAIL
// $ go test
// --- FAIL: TestAdd (0.00s)
// panic: not implemented

// Step 4: 写最少代码实现（GREEN）
func Add(a, b int) int {
    return a + b
}

// Step 5: 再跑测试 —— 确认 PASS
// $ go test
// PASS

// Step 6: 按需重构，确认测试依然通过
```

## 表驱动测试

Go 测试的标准模式。以最少的代码获得全面的覆盖。

```go
func TestAdd(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        expected int
    }{
        {"positive numbers", 2, 3, 5},
        {"negative numbers", -1, -2, -3},
        {"zero values", 0, 0, 0},
        {"mixed signs", -1, 1, 0},
        {"large numbers", 1000000, 2000000, 3000000},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := Add(tt.a, tt.b)
            if got != tt.expected {
                t.Errorf("Add(%d, %d) = %d; want %d",
                    tt.a, tt.b, got, tt.expected)
            }
        })
    }
}
```

### 带错误用例的表驱动测试

```go
func TestParseConfig(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    *Config
        wantErr bool
    }{
        {
            name:  "valid config",
            input: `{"host": "localhost", "port": 8080}`,
            want:  &Config{Host: "localhost", Port: 8080},
        },
        {
            name:    "invalid JSON",
            input:   `{invalid}`,
            wantErr: true,
        },
        {
            name:    "empty input",
            input:   "",
            wantErr: true,
        },
        {
            name:  "minimal config",
            input: `{}`,
            want:  &Config{}, // 零值 config
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParseConfig(tt.input)

            if tt.wantErr {
                if err == nil {
                    t.Error("expected error, got nil")
                }
                return
            }

            if err != nil {
                t.Fatalf("unexpected error: %v", err)
            }

            if !reflect.DeepEqual(got, tt.want) {
                t.Errorf("got %+v; want %+v", got, tt.want)
            }
        })
    }
}
```

## 子测试与子基准测试

### 组织相关测试

```go
func TestUser(t *testing.T) {
    // 所有子测试共享的 setup
    db := setupTestDB(t)

    t.Run("Create", func(t *testing.T) {
        user := &User{Name: "Alice"}
        err := db.CreateUser(user)
        if err != nil {
            t.Fatalf("CreateUser failed: %v", err)
        }
        if user.ID == "" {
            t.Error("expected user ID to be set")
        }
    })

    t.Run("Get", func(t *testing.T) {
        user, err := db.GetUser("alice-id")
        if err != nil {
            t.Fatalf("GetUser failed: %v", err)
        }
        if user.Name != "Alice" {
            t.Errorf("got name %q; want %q", user.Name, "Alice")
        }
    })

    t.Run("Update", func(t *testing.T) {
        // ...
    })

    t.Run("Delete", func(t *testing.T) {
        // ...
    })
}
```

### 并行子测试

```go
func TestParallel(t *testing.T) {
    tests := []struct {
        name  string
        input string
    }{
        {"case1", "input1"},
        {"case2", "input2"},
        {"case3", "input3"},
    }

    for _, tt := range tests {
        tt := tt // 捕获循环变量
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel() // 子测试并行运行
            result := Process(tt.input)
            // 断言...
            _ = result
        })
    }
}
```

## 测试辅助函数

### Helper Functions

```go
func setupTestDB(t *testing.T) *sql.DB {
    t.Helper() // 标记为 helper 函数

    db, err := sql.Open("sqlite3", ":memory:")
    if err != nil {
        t.Fatalf("failed to open database: %v", err)
    }

    // 测试结束时清理
    t.Cleanup(func() {
        db.Close()
    })

    // 执行 migration
    if _, err := db.Exec(schema); err != nil {
        t.Fatalf("failed to create schema: %v", err)
    }

    return db
}

func assertNoError(t *testing.T, err error) {
    t.Helper()
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
}

func assertEqual[T comparable](t *testing.T, got, want T) {
    t.Helper()
    if got != want {
        t.Errorf("got %v; want %v", got, want)
    }
}
```

### 临时文件与目录

```go
func TestFileProcessing(t *testing.T) {
    // 创建临时目录 —— 自动清理
    tmpDir := t.TempDir()

    // 创建测试文件
    testFile := filepath.Join(tmpDir, "test.txt")
    err := os.WriteFile(testFile, []byte("test content"), 0644)
    if err != nil {
        t.Fatalf("failed to create test file: %v", err)
    }

    // 执行测试
    result, err := ProcessFile(testFile)
    if err != nil {
        t.Fatalf("ProcessFile failed: %v", err)
    }

    // 断言...
    _ = result
}
```

## Golden 文件

将预期输出固化到 `testdata/` 下的文件中，做对比测试。

```go
var update = flag.Bool("update", false, "update golden files")

func TestRender(t *testing.T) {
    tests := []struct {
        name  string
        input Template
    }{
        {"simple", Template{Name: "test"}},
        {"complex", Template{Name: "test", Items: []string{"a", "b"}}},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := Render(tt.input)

            golden := filepath.Join("testdata", tt.name+".golden")

            if *update {
                // 更新 golden 文件：go test -update
                err := os.WriteFile(golden, got, 0644)
                if err != nil {
                    t.Fatalf("failed to update golden file: %v", err)
                }
            }

            want, err := os.ReadFile(golden)
            if err != nil {
                t.Fatalf("failed to read golden file: %v", err)
            }

            if !bytes.Equal(got, want) {
                t.Errorf("output mismatch:\ngot:\n%s\nwant:\n%s", got, want)
            }
        })
    }
}
```

## 基于接口的 Mock

### Interface-Based Mocking

```go
// 为依赖定义接口
type UserRepository interface {
    GetUser(id string) (*User, error)
    SaveUser(user *User) error
}

// 生产实现
type PostgresUserRepository struct {
    db *sql.DB
}

func (r *PostgresUserRepository) GetUser(id string) (*User, error) {
    // 真实数据库查询
}

// 测试用 mock 实现
type MockUserRepository struct {
    GetUserFunc  func(id string) (*User, error)
    SaveUserFunc func(user *User) error
}

func (m *MockUserRepository) GetUser(id string) (*User, error) {
    return m.GetUserFunc(id)
}

func (m *MockUserRepository) SaveUser(user *User) error {
    return m.SaveUserFunc(user)
}

// 使用 mock 的测试
func TestUserService(t *testing.T) {
    mock := &MockUserRepository{
        GetUserFunc: func(id string) (*User, error) {
            if id == "123" {
                return &User{ID: "123", Name: "Alice"}, nil
            }
            return nil, ErrNotFound
        },
    }

    service := NewUserService(mock)

    user, err := service.GetUserProfile("123")
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
    if user.Name != "Alice" {
        t.Errorf("got name %q; want %q", user.Name, "Alice")
    }
}
```

## 基准测试

### 基础 Benchmark

```go
func BenchmarkProcess(b *testing.B) {
    data := generateTestData(1000)
    b.ResetTimer() // 不计算 setup 时间

    for i := 0; i < b.N; i++ {
        Process(data)
    }
}

// 运行：go test -bench=BenchmarkProcess -benchmem
// 输出：BenchmarkProcess-8   10000   105234 ns/op   4096 B/op   10 allocs/op
```

### 不同输入规模的 Benchmark

```go
func BenchmarkSort(b *testing.B) {
    sizes := []int{100, 1000, 10000, 100000}

    for _, size := range sizes {
        b.Run(fmt.Sprintf("size=%d", size), func(b *testing.B) {
            data := generateRandomSlice(size)
            b.ResetTimer()

            for i := 0; i < b.N; i++ {
                // 拷贝一份，避免对已排序数据排序
                tmp := make([]int, len(data))
                copy(tmp, data)
                sort.Ints(tmp)
            }
        })
    }
}
```

### 内存分配 Benchmark

```go
func BenchmarkStringConcat(b *testing.B) {
    parts := []string{"hello", "world", "foo", "bar", "baz"}

    b.Run("plus", func(b *testing.B) {
        for i := 0; i < b.N; i++ {
            var s string
            for _, p := range parts {
                s += p
            }
            _ = s
        }
    })

    b.Run("builder", func(b *testing.B) {
        for i := 0; i < b.N; i++ {
            var sb strings.Builder
            for _, p := range parts {
                sb.WriteString(p)
            }
            _ = sb.String()
        }
    })

    b.Run("join", func(b *testing.B) {
        for i := 0; i < b.N; i++ {
            _ = strings.Join(parts, "")
        }
    })
}
```

## 模糊测试（Go 1.18+）

### 基础 Fuzz Test

```go
func FuzzParseJSON(f *testing.F) {
    // 添加种子语料
    f.Add(`{"name": "test"}`)
    f.Add(`{"count": 123}`)
    f.Add(`[]`)
    f.Add(`""`)

    f.Fuzz(func(t *testing.T, input string) {
        var result map[string]interface{}
        err := json.Unmarshal([]byte(input), &result)

        if err != nil {
            // 随机输入下，非法 JSON 属于预期
            return
        }

        // 如果解析成功，重新编码也应成功
        _, err = json.Marshal(result)
        if err != nil {
            t.Errorf("Marshal failed after successful Unmarshal: %v", err)
        }
    })
}

// 运行：go test -fuzz=FuzzParseJSON -fuzztime=30s
```

### 多输入的 Fuzz Test

```go
func FuzzCompare(f *testing.F) {
    f.Add("hello", "world")
    f.Add("", "")
    f.Add("abc", "abc")

    f.Fuzz(func(t *testing.T, a, b string) {
        result := Compare(a, b)

        // 性质：Compare(a, a) 始终应为 0
        if a == b && result != 0 {
            t.Errorf("Compare(%q, %q) = %d; want 0", a, b, result)
        }

        // 性质：Compare(a, b) 与 Compare(b, a) 符号相反
        reverse := Compare(b, a)
        if (result > 0 && reverse >= 0) || (result < 0 && reverse <= 0) {
            if result != 0 || reverse != 0 {
                t.Errorf("Compare(%q, %q) = %d, Compare(%q, %q) = %d; inconsistent",
                    a, b, result, b, a, reverse)
            }
        }
    })
}
```

## 测试覆盖率

### 运行覆盖率

```bash
# 基础覆盖率
go test -cover ./...

# 生成覆盖率 profile
go test -coverprofile=coverage.out ./...

# 在浏览器查看覆盖率
go tool cover -html=coverage.out

# 按函数查看覆盖率
go tool cover -func=coverage.out

# 叠加竞态检测
go test -race -coverprofile=coverage.out ./...
```

### 覆盖率目标

| 代码类型 | 目标 |
|---------|------|
| 关键业务逻辑 | 100% |
| 对外 API | 90%+ |
| 一般代码 | 80%+ |
| 生成代码 | 排除 |

### 从覆盖率中排除生成代码

```go
//go:generate mockgen -source=interface.go -destination=mock_interface.go

// 在覆盖率 profile 中用 build tag 排除：
// go test -cover -tags=!generate ./...
```

## HTTP Handler 测试

```go
func TestHealthHandler(t *testing.T) {
    // 构造请求
    req := httptest.NewRequest(http.MethodGet, "/health", nil)
    w := httptest.NewRecorder()

    // 调用 handler
    HealthHandler(w, req)

    // 检查响应
    resp := w.Result()
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        t.Errorf("got status %d; want %d", resp.StatusCode, http.StatusOK)
    }

    body, _ := io.ReadAll(resp.Body)
    if string(body) != "OK" {
        t.Errorf("got body %q; want %q", body, "OK")
    }
}

func TestAPIHandler(t *testing.T) {
    tests := []struct {
        name       string
        method     string
        path       string
        body       string
        wantStatus int
        wantBody   string
    }{
        {
            name:       "get user",
            method:     http.MethodGet,
            path:       "/users/123",
            wantStatus: http.StatusOK,
            wantBody:   `{"id":"123","name":"Alice"}`,
        },
        {
            name:       "not found",
            method:     http.MethodGet,
            path:       "/users/999",
            wantStatus: http.StatusNotFound,
        },
        {
            name:       "create user",
            method:     http.MethodPost,
            path:       "/users",
            body:       `{"name":"Bob"}`,
            wantStatus: http.StatusCreated,
        },
    }

    handler := NewAPIHandler()

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            var body io.Reader
            if tt.body != "" {
                body = strings.NewReader(tt.body)
            }

            req := httptest.NewRequest(tt.method, tt.path, body)
            req.Header.Set("Content-Type", "application/json")
            w := httptest.NewRecorder()

            handler.ServeHTTP(w, req)

            if w.Code != tt.wantStatus {
                t.Errorf("got status %d; want %d", w.Code, tt.wantStatus)
            }

            if tt.wantBody != "" && w.Body.String() != tt.wantBody {
                t.Errorf("got body %q; want %q", w.Body.String(), tt.wantBody)
            }
        })
    }
}
```

## 测试命令

```bash
# 运行所有测试
go test ./...

# 详细输出
go test -v ./...

# 运行特定测试
go test -run TestAdd ./...

# 按模式匹配运行
go test -run "TestUser/Create" ./...

# 启用竞态检测
go test -race ./...

# 运行带覆盖率的测试
go test -cover -coverprofile=coverage.out ./...

# 只运行短测试
go test -short ./...

# 带超时运行
go test -timeout 30s ./...

# 运行 benchmark
go test -bench=. -benchmem ./...

# 运行 fuzzing
go test -fuzz=FuzzParse -fuzztime=30s ./...

# 多次运行（用于 flaky 测试排查）
go test -count=10 ./...
```

## 最佳实践

**DO：**
- 先写测试（TDD）
- 使用表驱动测试追求全面覆盖
- 测试行为，不测试实现
- helper 函数内调用 `t.Helper()`
- 独立的测试用 `t.Parallel()`
- 用 `t.Cleanup()` 清理资源
- 用能描述场景的测试名

**DON'T：**
- 直接测试私有函数（通过公开 API 测）
- 在测试中使用 `time.Sleep()`（改用 channel 或条件）
- 放任 flaky 测试不管（修掉或删掉）
- 什么都 mock（能做集成测试就优先集成测试）
- 跳过错误路径的测试

## 与 CI/CD 集成

```yaml
# GitHub Actions 示例
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-go@v5
      with:
        go-version: '1.22'

    - name: Run tests
      run: go test -race -coverprofile=coverage.out ./...

    - name: Check coverage
      run: |
        go tool cover -func=coverage.out | grep total | awk '{print $3}' | \
        awk -F'%' '{if ($1 < 80) exit 1}'
```

**请记住**：测试即文档。它们展示代码该被如何使用。写得清晰，并持续同步。
