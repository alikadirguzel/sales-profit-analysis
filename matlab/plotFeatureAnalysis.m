function plotFeatureAnalysis(R, outDir, figVisible, targetVar)
%PLOTFEATUREANALYSIS  Save the per-feature figure set to results/<Feature>/.
%
%   PNG files:
%     boxplot.png, violin.png, distribution.png, mean_ci.png,
%     ecdf.png, permutation_anova.png, qqplots.png, dashboard.png

    if R.skipped
        return;
    end
    if nargin < 3 || isempty(figVisible)
        figVisible = 'off';
    end
    if nargin < 4 || isempty(targetVar)
        targetVar = 'Profit';
    end

    if ~isfolder(outDir)
        mkdir(outDir);
    end

    y = R.y;
    g = R.group;
    cats = cellstr(R.groups);
    k = R.k;
    cols = groupColors(k);
    feat = char(R.feature);

    saveFig(@() figBoxplot(g, y, feat, targetVar, cols), fullfile(outDir, 'boxplot.png'), figVisible);
    saveFig(@() figViolin(g, y, feat, targetVar), fullfile(outDir, 'violin.png'), figVisible);
    saveFig(@() figDistribution(y, R.gidx, cats, feat, targetVar, cols), ...
        fullfile(outDir, 'distribution.png'), figVisible);
    saveFig(@() figMeanCI(R.desc, feat, targetVar, cols), fullfile(outDir, 'mean_ci.png'), figVisible);
    saveFig(@() figECDF(y, R.gidx, cats, feat, targetVar, cols), fullfile(outDir, 'ecdf.png'), figVisible);
    saveFig(@() figPermutation(R.perm, feat), fullfile(outDir, 'permutation_anova.png'), figVisible);
    saveFig(@() figQQ(y, R.gidx, cats, feat, targetVar), fullfile(outDir, 'qqplots.png'), figVisible);
    saveFig(@() figDashboard(R, targetVar, cols), fullfile(outDir, 'dashboard.png'), figVisible);
end

function saveFig(drawFun, path, figVisible)
    fig = figure('Color', 'w', 'Visible', figVisible, ...
        'Position', [80 80 1280 720]);
    try
        drawFun();
        applyFonts(fig);
        exportgraphics(fig, path, 'Resolution', 200);
    catch ME
        fprintf('  Figure not saved (%s): %s\n', path, ME.message);
    end
    close(fig);
end

function figBoxplot(g, y, feat, targetVar, cols)
    boxchart(g, y, 'BoxFaceColor', [0.20 0.45 0.70], 'MarkerStyle', '.');
    hold on;
    yline(0, '--', 'Color', [0.75 0.20 0.20], 'LineWidth', 1);
    hold off;
    grid on;
    xlabel(feat, 'Interpreter', 'none');
    ylabel(sprintf('%s (TL)', targetVar), 'Interpreter', 'none');
    title(sprintf('Boxplot of %s by %s', targetVar, feat), 'Interpreter', 'none');
    xtickangle(25);
    ax = gca; ax.YAxis.Exponent = 0;
    % Color boxes if MATLAB supports BoxFaceColor mapping via scatter of means
    cats = categories(g);
    for i = 1:numel(cats)
        % keep default; colormap used in other plots
        if i > numel(cols), break; end
    end
end

function figViolin(g, y, feat, targetVar)
    ok = false;
    try
        violinplot(g, y);
        ok = true;
    catch
        try
            violinplot(y, g);
            ok = true;
        catch
            ok = false;
        end
    end
    if ~ok
        boxchart(g, y, 'BoxFaceColor', [0.20 0.45 0.70], 'MarkerStyle', '.');
        title(sprintf('Violin not available; boxplot of %s by %s', targetVar, feat), ...
            'Interpreter', 'none');
    else
        title(sprintf('Violin plot of %s by %s', targetVar, feat), 'Interpreter', 'none');
    end
    grid on;
    xlabel(feat, 'Interpreter', 'none');
    ylabel(sprintf('%s (TL)', targetVar), 'Interpreter', 'none');
    xtickangle(25);
    ax = gca; ax.YAxis.Exponent = 0;
end

function figDistribution(y, gidx, cats, feat, targetVar, cols)
    k = numel(cats);
    nCols = min(4, k);
    nRowsHist = ceil(k / nCols);
    tiledlayout(nRowsHist + 1, nCols, 'Padding', 'compact', 'TileSpacing', 'compact');

    for i = 1:k
        nexttile;
        yi = y(gidx == i);
        histogram(yi, 'FaceColor', cols(i, :), 'EdgeColor', 'none', 'FaceAlpha', 0.85);
        hold on;
        xline(mean(yi), 'k-', 'LineWidth', 1.2);
        hold off;
        grid on;
        title(cats{i}, 'Interpreter', 'none', 'FontSize', 9);
        xlabel(targetVar, 'Interpreter', 'none');
        ylabel('Count');
        ax = gca; ax.YAxis.Exponent = 0; ax.XAxis.Exponent = 0;
    end
    nPad = nRowsHist * nCols - k;
    for j = 1:nPad
        nexttile;
        axis off;
    end

    nexttile([1 nCols]);
    hold on;
    h = gobjects(k, 1);
    for i = 1:k
        yi = y(gidx == i);
        if numel(yi) < 5 || std(yi) == 0
            continue;
        end
        [f, xi] = ksdensity(yi);
        h(i) = plot(xi, f, 'Color', cols(i, :), 'LineWidth', 1.8);
    end
    hold off;
    grid on;
    xlabel(sprintf('%s (TL)', targetVar), 'Interpreter', 'none');
    ylabel('Density');
    title(sprintf('Kernel density of %s by %s', targetVar, feat), 'Interpreter', 'none');
    okH = arrayfun(@(z) isgraphics(z), h);
    if any(okH)
        legend(h(okH), cats(okH), 'Interpreter', 'none', 'Location', 'best');
    end
    ax = gca; ax.XAxis.Exponent = 0;
end

function figMeanCI(desc, feat, targetVar, cols)
    [~, ord] = sort(desc.Mean, 'descend');
    d = desc(ord, :);
    k = height(d);
    x = 1:k;
    errLo = d.Mean - d.CI_Low;
    errHi = d.CI_High - d.Mean;
    hold on;
    for i = 1:k
        errorbar(x(i), d.Mean(i), errLo(i), errHi(i), 'o', ...
            'Color', cols(i, :), 'MarkerFaceColor', cols(i, :), ...
            'LineWidth', 1.6, 'MarkerSize', 7, 'CapSize', 8);
    end
    yline(0, '--', 'Color', [0.5 0.5 0.5]);
    hold off;
    grid on;
    set(gca, 'XTick', x, 'XTickLabel', d.Group, 'TickLabelInterpreter', 'none');
    xtickangle(25);
    xlabel(feat, 'Interpreter', 'none');
    ylabel(sprintf('Mean %s (TL)', targetVar), 'Interpreter', 'none');
    title(sprintf('Group mean %s with 95%% t-interval — %s', targetVar, feat), ...
        'Interpreter', 'none');
    ax = gca; ax.YAxis.Exponent = 0;
end

function figECDF(y, gidx, cats, feat, targetVar, cols)
    k = numel(cats);
    hold on;
    h = gobjects(k, 1);
    for i = 1:k
        yi = y(gidx == i);
        if numel(yi) < 2
            continue;
        end
        [f, x] = ecdf(yi);
        h(i) = stairs(x, f, 'Color', cols(i, :), 'LineWidth', 1.6);
    end
    hold off;
    grid on;
    xlabel(sprintf('%s (TL)', targetVar), 'Interpreter', 'none');
    ylabel('F(x)');
    title(sprintf('Empirical CDF of %s by %s', targetVar, feat), 'Interpreter', 'none');
    okH = arrayfun(@(z) isgraphics(z), h);
    if any(okH)
        legend(h(okH), cats(okH), 'Interpreter', 'none', 'Location', 'best');
    end
    ax = gca; ax.XAxis.Exponent = 0;
    ylim([0 1]);
end

function figPermutation(perm, feat)
    histogram(perm.permF, 40, 'FaceColor', [0.45 0.62 0.80], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.9);
    hold on;
    xline(perm.Fobs, 'r-', 'LineWidth', 2.2);
    xline(perm.p95PermF, 'k--', 'LineWidth', 1.4);
    hold off;
    grid on;
    xlabel('F statistic', 'Interpreter', 'none');
    ylabel('Count');
    title(sprintf('Permutation F distribution — %s', feat), 'Interpreter', 'none');
    legend({sprintf('Permuted F (n = %d)', perm.nPermutations), ...
        sprintf('Observed F = %.3f', perm.Fobs), ...
        sprintf('95th percentile = %.3f', perm.p95PermF)}, ...
        'Location', 'best', 'Interpreter', 'none');
    txt = sprintf(['Observed F = %.4f\n' ...
        'Mean permuted F = %.4f\n' ...
        'Permutation p = %s\n' ...
        '(# F* >= F_obs + 1) / (nPerm + 1)'], ...
        perm.Fobs, perm.meanPermF, formatPValue(perm.p));
    yl = ylim;
    xl = xlim;
    text(xl(1) + 0.55 * diff(xl), yl(1) + 0.75 * diff(yl), txt, ...
        'FontSize', 10, 'BackgroundColor', 'w', 'EdgeColor', [0.6 0.6 0.6], ...
        'Interpreter', 'none');
end

function figQQ(y, gidx, cats, feat, targetVar)
    k = numel(cats);
    nCols = min(4, k);
    nRows = ceil(k / nCols);
    tiledlayout(nRows, nCols, 'Padding', 'compact', 'TileSpacing', 'compact');
    for i = 1:k
        nexttile;
        yi = y(gidx == i);
        qqplot(yi);
        grid on;
        title(cats{i}, 'Interpreter', 'none');
        xlabel('Normal quantile');
        ylabel(targetVar, 'Interpreter', 'none');
        ax = gca; ax.YAxis.Exponent = 0;
    end
    sgtitle(sprintf('Normal Q-Q plots of %s by %s', targetVar, feat), ...
        'Interpreter', 'none');
end

function figDashboard(R, targetVar, cols)
    tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    feat = char(R.feature);

    nexttile;
    boxchart(R.group, R.y, 'BoxFaceColor', [0.20 0.45 0.70], 'MarkerStyle', '.');
    grid on;
    title('Boxplot');
    ylabel(targetVar, 'Interpreter', 'none');
    xtickangle(25);
    ax = gca; ax.YAxis.Exponent = 0;

    nexttile;
    desc = R.desc;
    [~, ord] = sort(desc.Mean, 'descend');
    d = desc(ord, :);
    errorbar(1:height(d), d.Mean, d.Mean - d.CI_Low, d.CI_High - d.Mean, 'o', ...
        'LineWidth', 1.5, 'Color', [0.12 0.47 0.71], 'MarkerFaceColor', [0.12 0.47 0.71]);
    grid on;
    set(gca, 'XTick', 1:height(d), 'XTickLabel', d.Group, 'TickLabelInterpreter', 'none');
    xtickangle(25);
    title('Mean + 95% CI');
    ylabel(targetVar, 'Interpreter', 'none');
    ax = gca; ax.YAxis.Exponent = 0;

    nexttile;
    hold on;
    cats = cellstr(R.groups);
    h = gobjects(R.k, 1);
    for i = 1:R.k
        yi = R.y(R.gidx == i);
        if numel(yi) < 2, continue; end
        [f, x] = ecdf(yi);
        h(i) = stairs(x, f, 'Color', cols(i, :), 'LineWidth', 1.4);
    end
    hold off;
    grid on;
    title('ECDF');
    xlabel(targetVar, 'Interpreter', 'none');
    ylabel('F(x)');
    okH = arrayfun(@(z) isgraphics(z), h);
    if any(okH)
        legend(h(okH), cats(okH), 'Interpreter', 'none', 'Location', 'best', 'FontSize', 7);
    end

    nexttile;
    histogram(R.perm.permF, 35, 'FaceColor', [0.45 0.62 0.80], 'EdgeColor', 'none');
    hold on;
    xline(R.perm.Fobs, 'r-', 'LineWidth', 2);
    hold off;
    grid on;
    title(sprintf('Permutation F  (p = %s)', formatPValue(R.perm.p)));
    xlabel('F');
    ylabel('Count');

    sgtitle(sprintf('%s  |  ANOVA p = %s   Perm p = %s   eta^2 = %.3f', ...
        feat, formatPValue(R.anova.pClassical), formatPValue(R.perm.p), ...
        R.anova.etaSquared), 'Interpreter', 'none', 'FontWeight', 'bold');
end

function applyFonts(fig)
    set(findall(fig, '-property', 'FontName'), 'FontName', 'Arial');
    set(findall(fig, 'Type', 'axes'), 'FontSize', 10, 'LineWidth', 0.8);
end

function C = groupColors(k)
    base = [ ...
        0.12 0.47 0.71
        1.00 0.50 0.05
        0.17 0.63 0.17
        0.84 0.15 0.16
        0.58 0.40 0.74
        0.55 0.34 0.29
        0.89 0.47 0.76
        0.50 0.50 0.50
        0.74 0.74 0.13
        0.09 0.75 0.81
        0.20 0.29 0.55
        0.00 0.45 0.37];
    if k <= size(base, 1)
        C = base(1:k, :);
    else
        extra = hsv(k - size(base, 1));
        C = [base; extra];
    end
end
