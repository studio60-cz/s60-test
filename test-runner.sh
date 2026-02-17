#!/bin/bash
# Test Runner - Unified test execution script
# Usage: ./test-runner.sh <project> <suite> [options]

set -e

PROJECT=$1
SUITE=$2
HEADLESS=${3:-true}

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="/tmp/test-results"
mkdir -p "$RESULTS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ============================================
# VENOM E2E TESTS (Playwright)
# ============================================
function test_venom_e2e() {
    local suite=$1
    local headless=$2

    log_info "Running Venom E2E tests: $suite"

    cd /root/dev/s60-venom

    # Check if dev server is running
    if ! curl -s http://localhost:5173 > /dev/null 2>&1; then
        log_error "Venom dev server not running on localhost:5173"
        log_info "Start it with: cd /root/dev/s60-venom && npm run dev"
        return 1
    fi

    local test_file=""
    case "$suite" in
        "all")
            test_file=""
            ;;
        "navigation")
            test_file="tests/e2e/navigation.spec.ts"
            ;;
        "applications")
            test_file="tests/e2e/applications-*.spec.ts"
            ;;
        "filters")
            test_file="tests/e2e/applications-filters.spec.ts"
            ;;
        "crud")
            test_file="tests/e2e/crud-operations.spec.ts"
            ;;
        "errors")
            test_file="tests/e2e/error-handling.spec.ts"
            ;;
        *)
            test_file="tests/e2e/${suite}.spec.ts"
            ;;
    esac

    local result_file="$RESULTS_DIR/venom-e2e-${suite}-${TIMESTAMP}.json"

    if [ "$headless" = "true" ]; then
        npx playwright test $test_file --reporter=json --output="$result_file" 2>&1 | tee /tmp/playwright-output.log
    else
        npx playwright test $test_file --headed --reporter=json --output="$result_file" 2>&1 | tee /tmp/playwright-output.log
    fi

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_info "✅ Venom E2E tests PASSED"
        return 0
    else
        log_error "❌ Venom E2E tests FAILED"
        log_error "See details: /tmp/playwright-output.log"
        return 1
    fi
}

# ============================================
# VENOM UNIT TESTS (Vitest)
# ============================================
function test_venom_unit() {
    log_info "Running Venom unit tests"

    cd /root/dev/s60-venom

    npm run test -- --run --reporter=json --outputFile="$RESULTS_DIR/venom-unit-${TIMESTAMP}.json" 2>&1 | tee /tmp/vitest-output.log

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_info "✅ Venom unit tests PASSED"
        return 0
    else
        log_error "❌ Venom unit tests FAILED"
        return 1
    fi
}

# ============================================
# BADWOLF API TESTS
# ============================================
function test_badwolf_api() {
    local suite=$1

    log_info "Running BadWolf API tests: $suite"

    # Check if BadWolf is running
    if ! curl -s https://be.s60dev.cz/applications > /dev/null 2>&1; then
        log_error "BadWolf API not responding at https://be.s60dev.cz"
        return 1
    fi

    local result_file="$RESULTS_DIR/badwolf-api-${suite}-${TIMESTAMP}.json"

    case "$suite" in
        "all"|"smoke")
            test_badwolf_smoke
            ;;
        "applications")
            test_badwolf_applications
            ;;
        "courses")
            test_badwolf_courses
            ;;
        "locations")
            test_badwolf_locations
            ;;
        "clients")
            test_badwolf_clients
            ;;
        *)
            log_error "Unknown BadWolf test suite: $suite"
            return 1
            ;;
    esac
}

function test_badwolf_smoke() {
    log_info "Running BadWolf smoke tests..."

    local failed=0

    # Test /applications
    if curl -sf https://be.s60dev.cz/applications | jq -e 'type == "array"' > /dev/null; then
        log_info "  ✅ GET /applications"
    else
        log_error "  ❌ GET /applications"
        failed=$((failed + 1))
    fi

    # Test /courses
    if curl -sf https://be.s60dev.cz/courses | jq -e 'type == "array"' > /dev/null; then
        log_info "  ✅ GET /courses"
    else
        log_error "  ❌ GET /courses"
        failed=$((failed + 1))
    fi

    # Test /locations
    if curl -sf https://be.s60dev.cz/locations | jq -e 'type == "array"' > /dev/null; then
        log_info "  ✅ GET /locations"
    else
        log_error "  ❌ GET /locations"
        failed=$((failed + 1))
    fi

    # Test /clients
    if curl -sf https://be.s60dev.cz/clients | jq -e 'type == "array"' > /dev/null; then
        log_info "  ✅ GET /clients"
    else
        log_error "  ❌ GET /clients"
        failed=$((failed + 1))
    fi

    if [ $failed -eq 0 ]; then
        log_info "✅ BadWolf smoke tests PASSED"
        return 0
    else
        log_error "❌ BadWolf smoke tests FAILED ($failed failures)"
        return 1
    fi
}

function test_badwolf_applications() {
    log_info "Running BadWolf /applications tests..."

    local failed=0

    # Test list endpoint
    local count=$(curl -s https://be.s60dev.cz/applications | jq 'length')
    if [ "$count" -gt 0 ]; then
        log_info "  ✅ GET /applications returns $count items"
    else
        log_error "  ❌ GET /applications returns 0 items"
        failed=$((failed + 1))
    fi

    # Test with filters
    local filtered=$(curl -s "https://be.s60dev.cz/applications?limit=5" | jq 'length')
    if [ "$filtered" -le 5 ]; then
        log_info "  ✅ GET /applications?limit=5 respects limit"
    else
        log_error "  ❌ GET /applications?limit=5 returned $filtered items"
        failed=$((failed + 1))
    fi

    # Test detail endpoint
    local first_id=$(curl -s https://be.s60dev.cz/applications | jq -r '.[0].id')
    if curl -sf "https://be.s60dev.cz/applications/$first_id" | jq -e '.id' > /dev/null; then
        log_info "  ✅ GET /applications/:id returns detail"
    else
        log_error "  ❌ GET /applications/:id failed"
        failed=$((failed + 1))
    fi

    # Test 404
    if [ $(curl -s -o /dev/null -w "%{http_code}" "https://be.s60dev.cz/applications/00000000-0000-0000-0000-000000000000") -eq 404 ]; then
        log_info "  ✅ GET /applications/invalid returns 404"
    else
        log_error "  ❌ GET /applications/invalid should return 404"
        failed=$((failed + 1))
    fi

    [ $failed -eq 0 ] && return 0 || return 1
}

function test_badwolf_courses() {
    log_info "Running BadWolf /courses tests..."

    local count=$(curl -s https://be.s60dev.cz/courses | jq 'length')
    if [ "$count" -gt 0 ]; then
        log_info "  ✅ GET /courses returns $count courses"
        return 0
    else
        log_error "  ❌ GET /courses returns 0 courses"
        return 1
    fi
}

function test_badwolf_locations() {
    log_info "Running BadWolf /locations tests..."

    local count=$(curl -s https://be.s60dev.cz/locations | jq 'length')
    if [ "$count" -gt 0 ]; then
        log_info "  ✅ GET /locations returns $count locations"
        return 0
    else
        log_error "  ❌ GET /locations returns 0 locations"
        return 1
    fi
}

function test_badwolf_clients() {
    log_info "Running BadWolf /clients tests..."

    if curl -sf https://be.s60dev.cz/clients > /dev/null 2>&1; then
        local count=$(curl -s https://be.s60dev.cz/clients | jq 'length')
        log_info "  ✅ GET /clients returns $count clients"
        return 0
    else
        log_error "  ❌ GET /clients endpoint not available"
        return 1
    fi
}

# ============================================
# MAIN
# ============================================

if [ -z "$PROJECT" ]; then
    echo "Usage: $0 <project> <suite> [headless]"
    echo ""
    echo "Projects:"
    echo "  venom-e2e    - Venom E2E tests (Playwright)"
    echo "  venom-unit   - Venom unit tests (Vitest)"
    echo "  badwolf      - BadWolf API tests"
    echo ""
    echo "Suites (venom-e2e):"
    echo "  all          - All E2E tests"
    echo "  navigation   - Navigation tests"
    echo "  applications - Application tests"
    echo "  filters      - Filter tests"
    echo "  crud         - CRUD operations"
    echo "  errors       - Error handling"
    echo ""
    echo "Suites (badwolf):"
    echo "  smoke        - Quick smoke tests"
    echo "  applications - /applications endpoint tests"
    echo "  courses      - /courses endpoint tests"
    echo "  locations    - /locations endpoint tests"
    echo "  clients      - /clients endpoint tests"
    echo ""
    echo "Options:"
    echo "  headless     - true (default) or false"
    exit 1
fi

log_info "========================================="
log_info "Test Runner - $PROJECT / $SUITE"
log_info "========================================="

case "$PROJECT" in
    "venom-e2e")
        test_venom_e2e "$SUITE" "$HEADLESS"
        exit $?
        ;;
    "venom-unit")
        test_venom_unit
        exit $?
        ;;
    "badwolf")
        test_badwolf_api "$SUITE"
        exit $?
        ;;
    *)
        log_error "Unknown project: $PROJECT"
        exit 1
        ;;
esac
