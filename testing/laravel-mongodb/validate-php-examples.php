#!/usr/bin/env php
<?php

/**
 * Validates PHP syntax of all code blocks in the laravel-mongodb skill markdown files.
 *
 * Usage (from repo root):
 *   php testing/laravel-mongodb/validate-php-examples.php [path/to/skill]
 */

$skillDir = $argv[1] ?? 'skills/laravel-mongodb';

$mdFiles = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($skillDir, FilesystemIterator::SKIP_DOTS),
);

$passed  = 0;
$skipped = 0;
$failed  = 0;
$errors  = [];

foreach ($mdFiles as $file) {
    if ($file->getExtension() !== 'md') {
        continue;
    }

    $content = file_get_contents($file->getPathname());
    if ($content === false) {
        fwrite(STDERR, "Error: cannot read {$file->getPathname()}\n");
        exit(2);
    }

    preg_match_all('/```php\n(.*?)```/s', $content, $matches);

    foreach ($matches[1] as $i => $snippet) {
        $blockNum = $i + 1;
        $relPath  = $file->getPathname();
        $label    = "{$relPath} (block {$blockNum})";

        $snippet = rtrim($snippet);

        // Skip non-executable fragments (comparison snippets, bare import lists)
        if (
            !str_contains($snippet, '$')
            && !str_contains($snippet, 'class ')
            && !str_contains($snippet, 'function ')
            && !str_contains($snippet, 'return ')
            && !str_contains($snippet, 'declare')
            && !str_contains($snippet, 'namespace')
        ) {
            $skipped++;
            continue;
        }

        // Wrap orphan class-body snippets (properties/methods without a class declaration)
        $raw          = ltrim($snippet);
        $hasClassBody = (bool) preg_match('/^\s*(protected|public|private)\s+[\$\w]/m', $raw);
        $hasClass     = str_contains($raw, 'class ');
        $hasPHPTag    = str_starts_with($raw, '<?');

        if ($hasClassBody && !$hasClass) {
            $inner   = $hasPHPTag ? preg_replace('/^<\?php\s*/i', '', $raw) : $raw;
            $snippet = "<?php\nclass __Wrapper__ {\n" . $inner . "\n}";
        } elseif (!$hasPHPTag) {
            $snippet = "<?php\n" . $snippet;
        }

        // Write to a .php temp file directly (avoid tempnam orphan from appending .php)
        $tmpFile = tempnam(sys_get_temp_dir(), 'skill_php_');
        rename($tmpFile, $tmpFile . '.php');
        $tmpFile .= '.php';
        file_put_contents($tmpFile, $snippet);

        $output   = [];
        $exitCode = 0;
        exec(escapeshellarg(PHP_BINARY) . ' -l ' . escapeshellarg($tmpFile) . ' 2>&1', $output, $exitCode);
        unlink($tmpFile);

        if ($exitCode === 0) {
            $passed++;
        } else {
            $failed++;
            $outputClean = implode("\n", array_map(
                fn($l) => str_replace($tmpFile, '<snippet>', $l),
                $output,
            ));
            $relevantLines = array_filter(
                explode("\n", $outputClean),
                fn($l) => !str_starts_with(trim($l), 'No syntax errors'),
            );
            $errors[] = "FAIL  {$label}\n" .
                implode("\n", array_map(fn($l) => "      {$l}", $relevantLines));
        }
    }
}

foreach ($errors as $error) {
    echo $error . "\n\n";
}

$total = $passed + $failed + $skipped;
echo "Results: {$passed} passed, {$failed} failed, {$skipped} skipped (partial/comparison snippets), {$total} total\n";

exit($failed > 0 ? 1 : 0);
