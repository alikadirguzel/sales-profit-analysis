function printFeatureReport(R, opts, fid)
%PRINTFEATUREREPORT  Command-window (and optional file) report for one feature.

    if nargin < 3
        fid = 1;
    end
    fids = unique([1, fid]);
    fids = fids(fids > 0);

    feat = char(R.feature);
    banner(fids, sprintf('FEATURE ANALYSIS: %s', upper(feat)));

    if R.skipped
        both(fids, 'SKIPPED: %s\n', R.skipReason);
        return;
    end

    both(fids, 'Groups:\n');
    for i = 1:R.k
        both(fids, '  %s\n', R.groups(i));
    end
    both(fids, '\nSample sizes:\n');
    for i = 1:R.k
        both(fids, '  %-22s = %d\n', R.groups(i), R.nG(i));
    end
    if ~isempty(R.warnings)
        both(fids, '\nWarnings:\n');
        for i = 1:numel(R.warnings)
            both(fids, '  - %s\n', R.warnings(i));
        end
    end

    section(fids, 'DESCRIPTIVE STATISTICS');
    both(fids, '%-22s %6s %10s %10s %10s %22s\n', ...
        'Group', 'N', 'Mean', 'Median', 'Std', '95% CI');
    both(fids, '%s\n', repmat('-', 1, 86));
    for i = 1:R.k
        both(fids, '%-22s %6d %10.2f %10.2f %10.2f  [%9.2f, %9.2f]\n', ...
            R.desc.Group(i), R.desc.N(i), R.desc.Mean(i), R.desc.Median(i), ...
            R.desc.Std(i), R.desc.CI_Low(i), R.desc.CI_High(i));
    end
    both(fids, '\nMean +/- std and other moments:\n');
    for i = 1:R.k
        both(fids, ['  %s: mean+/-std = %.2f +/- %.2f | var = %.2f | min = %.2f | ' ...
            'max = %.2f | Q1 = %.2f | Q3 = %.2f | IQR = %.2f | SE = %.2f | CV = %.3f | ' ...
            'skew = %.3f | excess kurtosis = %.3f\n'], ...
            R.desc.Group(i), R.desc.Mean(i), R.desc.Std(i), R.desc.Variance(i), ...
            R.desc.Min(i), R.desc.Max(i), R.desc.Q1(i), R.desc.Q3(i), R.desc.IQR(i), ...
            R.desc.SE(i), R.desc.CV(i), R.desc.Skewness(i), R.desc.ExcessKurtosis(i));
    end

    section(fids, 'NORMALITY');
    both(fids, 'H0: Group data come from a normal distribution.\n');
    both(fids, 'H1: Group data do not come from a normal distribution.\n');
    both(fids, '%s\n\n', R.normality.shapiroNote);
    Nrm = R.normality.rows;
    for i = 1:height(Nrm)
        both(fids, 'Group: %s\n', Nrm.Group(i));
        both(fids, '  N = %d\n', Nrm.N(i));
        both(fids, '  Normality test = %s\n', Nrm.TestPrimary(i));
        both(fids, '  p = %s\n', formatPValue(Nrm.pPrimary(i)));
        both(fids, '  Lilliefors p = %s\n', formatPValue(Nrm.pLillie(i)));
        both(fids, '  Decision = %s\n', Nrm.Decision(i));
        both(fids, '  %s\n\n', Nrm.Note(i));
    end

    section(fids, 'OUTLIERS (detected, not removed)');
    both(fids, '%s\n\n', R.outliers.method);
    both(fids, '%-22s %6s %14s %16s %10s %12s\n', ...
        'Group', 'N', 'IQR outliers', 'IQR percent', 'z>3', 'z>3 percent');
    OT = R.outliers.table;
    for i = 1:height(OT)
        both(fids, '%-22s %6d %14d %15.2f%% %10d %11.2f%%\n', ...
            OT.Group(i), OT.N(i), OT.N_IQR(i), OT.Pct_IQR(i), OT.N_Z3(i), OT.Pct_Z3(i));
    end

    section(fids, 'VARIANCE HOMOGENEITY');
    both(fids, 'H0: All group variances are equal.\n');
    both(fids, 'H1: At least one group variance differs.\n\n');
    both(fids, 'Levene''s Test (%s)\n', R.variance.levene.method);
    both(fids, '  Statistic = %.4f\n', R.variance.levene.statistic);
    both(fids, '  p-value   = %s\n', formatPValue(R.variance.levene.p));
    both(fids, '  Decision  = %s\n\n', rejectTxt(R.variance.levene.rejectH0));
    both(fids, 'Brown-Forsythe (median version): statistic = %.4f, p = %s, %s\n', ...
        R.variance.brownForsythe.statistic, formatPValue(R.variance.brownForsythe.p), ...
        rejectTxt(R.variance.brownForsythe.rejectH0));
    both(fids, 'Bartlett p-value (sensitive to non-normality) = %s\n', ...
        formatPValue(R.variance.bartlettP));
    both(fids, 'Levene is the primary homogeneity test.\n');

    section(fids, 'CLASSICAL ANOVA');
    A = R.anova;
    both(fids, 'Feature = %s\n\n', feat);
    both(fids, 'H0: all group means of %s are equal.\n', opts.targetVar);
    both(fids, 'H1: at least one group mean differs.\n\n');
    both(fids, '%-12s %14s %8s %14s %10s %12s\n', ...
        'Source', 'SS', 'df', 'MS', 'F', 'p-value');
    both(fids, '%s\n', repmat('-', 1, 76));
    both(fids, '%-12s %14.4f %8d %14.4f %10.4f %12s\n', ...
        'Between', A.ssBetween, A.dfBetween, A.msBetween, A.F, formatPValue(A.pClassical));
    both(fids, '%-12s %14.4f %8d %14.4f\n', 'Within', A.ssWithin, A.dfWithin, A.msWithin);
    both(fids, '%-12s %14.4f %8d\n\n', 'Total', A.ssTotal, A.dfTotal);
    both(fids, 'F = %.4f\n', A.F);
    both(fids, 'df1 = %d, df2 = %d\n', A.dfBetween, A.dfWithin);
    both(fids, 'p-value = %s\n', formatPValue(A.pClassical));
    both(fids, 'anova1 cross-check p = %s\n', formatPValue(A.pToolbox));
    both(fids, 'Decision = %s\n\n', rejectTxt(A.rejectH0));
    both(fids, 'Eta squared  eta^2   = %.4f\n', A.etaSquared);
    both(fids, 'Omega squared omega^2 = %.4f\n', A.omegaSquared);
    both(fids, 'Interpretation: %s explains approximately %.2f%% of the variance in profit.\n', ...
        feat, 100 * A.etaSquared);
    both(fids, ['Effect-size cutoffs (e.g. 0.01/0.06/0.14) are context-dependent; ', ...
        'the numeric eta^2/omega^2 values are the quantities to report.\n']);

    section(fids, 'PERMUTATION ANOVA');
    P = R.perm;
    both(fids, ['H0: There is no systematic group effect on the profit distribution.\n' ...
        '    Similar F values can arise by chance after shuffling group labels.\n']);
    both(fids, 'H1: There is a systematic difference among groups.\n\n');
    both(fids, 'Permutations     = %d\n', P.nPermutations);
    both(fids, 'Observed F       = %.4f\n', P.Fobs);
    both(fids, 'Mean permuted F  = %.4f\n', P.meanPermF);
    both(fids, '95th percentile  = %.4f\n', P.p95PermF);
    both(fids, 'n(F* >= F_obs)   = %d\n', P.nExtreme);
    both(fids, 'Permutation p    = (nExtreme + 1) / (nPerm + 1) = %s\n', formatPValue(P.p));
    both(fids, 'alpha            = %.2f\n', opts.alpha);
    if P.rejectH0
        both(fids, ['Decision: H0 rejected.\n' ...
            'There is statistically significant evidence that at least one group differs.\n']);
    else
        both(fids, ['Decision: H0 cannot be rejected.\n' ...
            'There is insufficient statistical evidence that the groups differ.\n']);
    end

    section(fids, 'KRUSKAL-WALLIS (robustness check)');
    both(fids, 'H0: The groups have the same distribution of %s (equal stochastic dominance / ranks).\n', ...
        opts.targetVar);
    both(fids, 'H1: At least one group differs in distribution.\n');
    both(fids, 'This is NOT used as an automatic replacement for ANOVA.\n\n');
    both(fids, 'H = %.4f\n', R.kw.H);
    both(fids, 'df = %d\n', R.kw.df);
    both(fids, 'p-value = %s\n', formatPValue(R.kw.p));
    both(fids, 'epsilon^2 = %.4f\n', R.kw.epsilonSquared);

    section(fids, 'POST-HOC');
    both(fids, '%s\n', R.posthoc.reason);
    if R.posthoc.performed
        printPairTable(fids, R.posthoc.tukey, 'Tukey-Kramer (means)');
        if ~isempty(R.posthoc.dunn)
            printPairTable(fids, R.posthoc.dunn, 'Dunn-Sidak (ranks)');
        end
    end

    section(fids, 'MEAN COMPARISON SNAPSHOT');
    both(fids, 'Feature: %s\n\n', feat);
    for i = 1:R.k
        both(fids, '  %-22s Mean Profit = %.2f\n', R.desc.Group(i), R.desc.Mean(i));
    end
    both(fids, '\nANOVA p-value            = %s\n', formatPValue(A.pClassical));
    both(fids, 'Permutation ANOVA p-value = %s\n', formatPValue(P.p));
    both(fids, 'Kruskal-Wallis p-value    = %s\n', formatPValue(R.kw.p));
    both(fids, 'eta^2                     = %.4f\n', A.etaSquared);

    section(fids, 'FINAL INTERPRETATION');
    both(fids, '%s\n', R.interpretation);
    both(fids, '\n===========================================================\n\n');
end

function printPairTable(fids, T, label)
    if isempty(T)
        return;
    end
    both(fids, '\n%s\n', label);
    both(fids, '%-40s %12s %24s %12s %6s\n', ...
        'Comparison', 'Mean Diff', 'CI95%', 'p-adj', 'Sig');
    both(fids, '%s\n', repmat('-', 1, 100));
    for i = 1:height(T)
        cmp = T.Group1(i) + " vs " + T.Group2(i);
        ci = sprintf('[%.2f, %.2f]', T.CI_Low(i), T.CI_High(i));
        if T.Significant(i), sig = 'YES'; else, sig = 'no'; end
        both(fids, '%-40s %12.2f %24s %12s %6s\n', ...
            cmp, T.MeanDiff(i), ci, formatPValue(T.p_adj(i)), sig);
    end
end

function banner(fids, titleStr)
    both(fids, '\n===========================================================\n');
    both(fids, '%s\n', titleStr);
    both(fids, '===========================================================\n\n');
end

function section(fids, name)
    both(fids, '\n-----------------------------------------------------------\n');
    both(fids, '%s\n', name);
    both(fids, '-----------------------------------------------------------\n\n');
end

function both(fids, varargin)
    for i = 1:numel(fids)
        fprintf(fids(i), varargin{:});
    end
end

function s = rejectTxt(tf)
    if tf
        s = 'Reject H0';
    else
        s = 'Fail to Reject H0';
    end
end
