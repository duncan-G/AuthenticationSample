#!/bin/bash

# Developer onboarding test script
# Simulates a new developer following the documentation to set up the system

echo "🧪 Testing developer onboarding documentation..."

ERRORS=0
WARNINGS=0

# Function to log test results
log_test() {
    local status="$1"
    local message="$2"
    
    if [ "$status" = "PASS" ]; then
        echo "✅ PASS: $message"
    elif [ "$status" = "FAIL" ]; then
        echo "❌ FAIL: $message"
        ((ERRORS++))
    elif [ "$status" = "WARN" ]; then
        echo "⚠️  WARN: $message"
        ((WARNINGS++))
    fi
}

# Test 1: Check if main entry points exist and are accessible
echo "📋 Testing main entry points..."

if [ -f "docs/README.md" ]; then
    log_test "PASS" "Main README exists"
else
    log_test "FAIL" "Main README missing"
fi

if [ -f "docs/index.md" ]; then
    log_test "PASS" "Feature index exists"
else
    log_test "FAIL" "Feature index missing"
fi

if [ -f "docs/navigation.md" ]; then
    log_test "PASS" "Navigation index exists"
else
    log_test "FAIL" "Navigation index missing"
fi

# Test 2: Check developer setup guide completeness
echo "🚀 Testing developer setup guide..."

if [ -f "docs/guides/developer-setup.md" ]; then
    log_test "PASS" "Developer setup guide exists"
    
    # Check for essential sections
    if grep -q "## Prerequisites" docs/guides/developer-setup.md; then
        log_test "PASS" "Prerequisites section exists"
    else
        log_test "FAIL" "Prerequisites section missing"
    fi
    
    if grep -q "## Environment Configuration" docs/guides/developer-setup.md; then
        log_test "PASS" "Environment configuration section exists"
    else
        log_test "WARN" "Environment configuration section missing"
    fi
    
    # Check for essential commands
    if grep -q "./setup.sh" docs/guides/developer-setup.md; then
        log_test "PASS" "Setup script mentioned"
    else
        log_test "FAIL" "Setup script not mentioned"
    fi
    
    if grep -q "./start.sh" docs/guides/developer-setup.md; then
        log_test "PASS" "Start script mentioned"
    else
        log_test "FAIL" "Start script not mentioned"
    fi
else
    log_test "FAIL" "Developer setup guide missing"
fi

# Test 3: Check architecture documentation
echo "🏛️ Testing architecture documentation..."

if [ -f "docs/guides/architecture-overview.md" ]; then
    log_test "PASS" "Architecture overview exists"
    
    # Check for system components
    if grep -q -i "microservices\|grpc\|envoy" docs/guides/architecture-overview.md; then
        log_test "PASS" "Key architecture components mentioned"
    else
        log_test "WARN" "Key architecture components not clearly described"
    fi
else
    log_test "FAIL" "Architecture overview missing"
fi

# Test 4: Check feature documentation completeness
echo "📚 Testing feature documentation..."

# Check authentication features
AUTH_FEATURES=("user-signup" "user-signin" "verification-codes" "session-management" "social-authentication")
for feature in "${AUTH_FEATURES[@]}"; do
    if [ -f "docs/features/authentication/$feature.md" ]; then
        log_test "PASS" "Authentication feature documented: $feature"
    else
        log_test "FAIL" "Authentication feature missing: $feature"
    fi
done

# Check security features
SECURITY_FEATURES=("rate-limiting" "jwt-validation" "error-handling" "cors-configuration" "input-validation")
for feature in "${SECURITY_FEATURES[@]}"; do
    if [ -f "docs/features/security/$feature.md" ]; then
        log_test "PASS" "Security feature documented: $feature"
    else
        log_test "FAIL" "Security feature missing: $feature"
    fi
done

# Test 5: Check cross-references and navigation
echo "🔗 Testing cross-references..."

# Check if main index has proper links
if grep -q "features/authentication/user-signup.md" docs/index.md; then
    log_test "PASS" "Main index has proper feature links"
else
    log_test "FAIL" "Main index missing proper feature links"
fi

# Check if feature READMEs exist
FEATURE_CATEGORIES=("authentication" "security" "infrastructure" "development" "api")
for category in "${FEATURE_CATEGORIES[@]}"; do
    if [ -f "docs/features/$category/README.md" ]; then
        log_test "PASS" "Feature category README exists: $category"
    else
        log_test "FAIL" "Feature category README missing: $category"
    fi
done

# Test 6: Check troubleshooting documentation
echo "🔧 Testing troubleshooting documentation..."

if [ -f "docs/guides/troubleshooting.md" ]; then
    log_test "PASS" "Troubleshooting guide exists"
    
    # Check for common issues
    if grep -q -i "common issues\|troubleshooting\|debug" docs/guides/troubleshooting.md; then
        log_test "PASS" "Troubleshooting content present"
    else
        log_test "WARN" "Troubleshooting content may be incomplete"
    fi
else
    log_test "FAIL" "Troubleshooting guide missing"
fi

# Test 7: Check code examples and commands
echo "💻 Testing code examples..."

CODE_EXAMPLE_COUNT=0
COMMAND_EXAMPLE_COUNT=0

# Count code blocks in key documentation
for file in docs/guides/developer-setup.md docs/features/authentication/user-signup.md docs/features/security/rate-limiting.md; do
    if [ -f "$file" ]; then
        code_blocks=$(grep -c '^```' "$file" || true)
        CODE_EXAMPLE_COUNT=$((CODE_EXAMPLE_COUNT + code_blocks / 2))
    fi
done

# Count bash command examples
COMMAND_EXAMPLE_COUNT=$(grep -r '\`\`\`bash' docs/ | wc -l || true)

if [ $CODE_EXAMPLE_COUNT -gt 10 ]; then
    log_test "PASS" "Sufficient code examples found ($CODE_EXAMPLE_COUNT blocks)"
else
    log_test "WARN" "Limited code examples found ($CODE_EXAMPLE_COUNT blocks)"
fi

if [ $COMMAND_EXAMPLE_COUNT -gt 5 ]; then
    log_test "PASS" "Sufficient command examples found ($COMMAND_EXAMPLE_COUNT commands)"
else
    log_test "WARN" "Limited command examples found ($COMMAND_EXAMPLE_COUNT commands)"
fi

# Test 8: Check template availability
echo "📄 Testing templates..."

TEMPLATES=("feature-template.md" "guide-template.md" "navigation-template.md")
for template in "${TEMPLATES[@]}"; do
    if [ -f "docs/templates/$template" ]; then
        log_test "PASS" "Template exists: $template"
    else
        log_test "FAIL" "Template missing: $template"
    fi
done

# Test 9: Simulate developer workflow
echo "🔄 Testing developer workflow simulation..."

# Check if a new developer can follow the path:
# README → Developer Setup → Architecture → Feature Integration

workflow_files=(
    "docs/README.md"
    "docs/guides/developer-setup.md"
    "docs/guides/architecture-overview.md"
    "docs/guides/feature-integration.md"
)

workflow_complete=true
for file in "${workflow_files[@]}"; do
    if [ ! -f "$file" ]; then
        workflow_complete=false
        log_test "FAIL" "Workflow file missing: $file"
    fi
done

if $workflow_complete; then
    log_test "PASS" "Complete developer workflow path exists"
fi

# Test 10: Check documentation freshness
echo "📅 Testing documentation freshness..."

# Check if main files have been updated recently (within last 30 days)
recent_files=0
for file in docs/README.md docs/index.md docs/guides/developer-setup.md; do
    if [ -f "$file" ]; then
        # Check if file was modified in last 30 days
        if [ $(find "$file" -mtime -30 | wc -l) -gt 0 ]; then
            ((recent_files++))
        fi
    fi
done

if [ $recent_files -gt 0 ]; then
    log_test "PASS" "Documentation appears to be recently updated ($recent_files files)"
else
    log_test "WARN" "Documentation may be outdated (no recent updates detected)"
fi

# Summary
echo ""
echo "📊 Developer onboarding test summary:"
echo "   Test failures: $ERRORS"
echo "   Test warnings: $WARNINGS"

# Calculate success rate
total_tests=30  # Approximate number of tests
passed_tests=$((total_tests - ERRORS))
success_rate=$((passed_tests * 100 / total_tests))

echo "   Success rate: $success_rate%"

echo ""
if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo "✅ All developer onboarding tests passed!"
        echo "🎉 Documentation is ready for new developer onboarding"
    else
        echo "⚠️  Developer onboarding tests passed with warnings"
        echo "📝 Consider addressing warnings to improve developer experience"
    fi
    exit 0
else
    echo "❌ Developer onboarding tests failed"
    echo "🚨 Critical issues found that would block new developer onboarding"
    exit 1
fi