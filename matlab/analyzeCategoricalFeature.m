function R = analyzeCategoricalFeature(y, group, featureName, opts)
%ANALYZECATEGORICALFEATURE  Full one-way analysis of Kar by one categorical factor.
%
%   Pipeline (in order):
%     descriptive -> outliers (detect only) -> normality -> variance
%     -> classical ANOVA -> effect size -> permutation ANOVA
%     -> Kruskal-Wallis robustness check -> post-hoc if overall test is significant
%
%   Outliers are never deleted automatically.

    y = double(y(:));
    group = removecats(categorical(string(group(:))));
    if ~isfield(opts, 'targetVar')
        opts.targetVar = 'Kar';
    end
    ok = isfinite(y) & ~isundefined(group);
    nDropped = sum(~ok);
    y = y(ok);
    group = removecats(group(ok));

    cats = categories(group);
    k = numel(cats);
    n = numel(y);
    gidx = grp2idx(group);

    R = struct();
    R.feature = string(featureName);
    R.groups = string(cats(:));
    R.n = n;
    R.k = k;
    R.nDropped = nDropped;
    R.warnings = strings(0, 1);
    R.skipped = false;
    R.skipReason = "";

    if nDropped > 0
        R.warnings(end+1) = sprintf( ...
            '%d rows dropped for this feature (non-finite %s or empty label).', ...
            nDropped, opts.targetVar);
    end
    if k < 2
        R.skipped = true;
        R.skipReason = "Fewer than 2 groups after cleaning.";
        return;
    end
    if n <= k
        R.skipped = true;
        R.skipReason = "Too few observations relative to the number of groups.";
        return;
    end

    nG = accumarray(gidx, 1, [k, 1]);
    R.nG = nG;
    if any(nG < 5)
        R.warnings(end+1) = sprintf( ...
            '%d group(s) have n < 5. Inferential results for those groups are unreliable.', ...
            sum(nG < 5));
    end

    % --- 1) Descriptive statistics ---
    R.desc = descriptiveGroupStats(y, gidx, cats, opts.confidenceLevel);

    % --- 2) Outlier detection (IQR + |z|>3). No deletion. ---
    R.outliers = outlierAnalysis(y, gidx, cats);

    % --- 3) Normality (Anderson-Darling + Lilliefors + QQ diagnostics) ---
    R.normality = normalityAnalysis(y, gidx, cats, opts.alpha);

    % --- 4) Variance homogeneity (Levene primary, Bartlett secondary) ---
    R.variance = varianceHomogeneity(y, gidx, k, opts.alpha);

    % --- 5-6) Classical one-way ANOVA + effect size ---
    R.anova = computeAnovaDecomposition(y, gidx);
    R.anova.alpha = opts.alpha;
    R.anova.rejectH0 = R.anova.pClassical < opts.alpha;

    % Cross-check against toolbox anova1 (should match F and p)
    [pToolbox, tblToolbox, statsAnova] = anova1(y, group, 'off');
    R.anova.pToolbox = pToolbox;
    R.anova.toolboxTable = tblToolbox;
    R.anova.statsObj = statsAnova;

    % --- 7) Permutation ANOVA (confirmatory, distribution-free for labels) ---
    R.perm = permutationAnova(y, gidx, opts.nPermutations, opts.alpha);

    % --- 8) Kruskal-Wallis as robustness check, not an automatic replacement ---
    [pKW, tblKW, statsKW] = kruskalwallis(y, group, 'off');
    R.kw = struct();
    R.kw.H = tblKW{2, 5};
    R.kw.p = pKW;
    R.kw.df = k - 1;
    R.kw.table = tblKW;
    R.kw.statsObj = statsKW;
    R.kw.alpha = opts.alpha;
    R.kw.rejectH0 = pKW < opts.alpha;
    % Epsilon-squared for KW: (H - k + 1) / (n - k)
    R.kw.epsilonSquared = (R.kw.H - k + 1) / (n - k);

    % Assumption summary (used for caveats, NOT to silently switch tests)
    R.assumptions = struct();
    R.assumptions.normalityOk = all(R.normality.rows.failToRejectH0);
    R.assumptions.leveneOk = ~R.variance.levene.rejectH0;
    R.assumptions.classicalAnovaAssumptionsOk = ...
        R.assumptions.leveneOk && all(nG >= 5);
    R.assumptions.note = "Classical ANOVA assumes independent observations, approximately normal group residuals, and homogeneous variances. Permutation ANOVA relaxes normality/equal-variance by using the permutation distribution of F. Kruskal-Wallis is a rank-based robustness check and is not treated as a drop-in replacement.";

    % --- 9) Post-hoc only if the overall mean-difference tests are significant ---
    overallSig = R.anova.rejectH0 || R.perm.rejectH0;
    R.posthoc = struct();
    R.posthoc.performed = false;
    R.posthoc.reason = "";
    R.posthoc.tukey = table();
    R.posthoc.dunn = table();

    if ~overallSig
        R.posthoc.reason = "Overall classical ANOVA and permutation ANOVA are both non-significant at alpha = " ...
            + string(opts.alpha) ...
            + ". Pairwise comparisons were not run (avoids extra false positives).";
    else
        R.posthoc.performed = true;
        R.posthoc.reason = "Overall test was significant (ANOVA p = " ...
            + string(formatPValue(R.anova.pClassical)) ...
            + ", permutation p = " + string(formatPValue(R.perm.p)) ...
            + "). Tukey-Kramer pairwise comparisons of means are reported.";
        try
            [cT, ~, ~, gnamesT] = multcompare(statsAnova, ...
                'CType', 'tukey-kramer', 'Alpha', opts.alpha, 'Display', 'off');
            R.posthoc.tukey = pairwiseTable(cT, gnamesT, featureName, 'Tukey-Kramer', opts.alpha);
        catch ME
            R.warnings(end+1) = "Tukey-Kramer failed: " + string(ME.message);
        end

        % Nonparametric pairwise complement when variance/normality look poor
        if ~R.variance.levene.rejectH0 && all(R.normality.rows.failToRejectH0)
            % assumptions look acceptable; Dunn is optional
        else
            R.posthoc.reason = R.posthoc.reason + " Levene and/or normality diagnostics suggest caution; Dunn-Sidak pairwise comparisons of ranks are also reported as a complement.";
            try
                [cD, ~, ~, gnamesD] = multcompare(statsKW, ...
                    'CType', 'dunn-sidak', 'Alpha', opts.alpha, 'Display', 'off');
                R.posthoc.dunn = pairwiseTable(cD, gnamesD, featureName, 'Dunn-Sidak', opts.alpha);
            catch ME
                R.warnings(end+1) = "Dunn-Sidak failed: " + string(ME.message);
            end
        end
    end

    % Largest observed mean difference (descriptive, not a test)
    [~, iMax] = max(R.desc.Mean);
    [~, iMin] = min(R.desc.Mean);
    R.largestMeanDiff = R.desc.Mean(iMax) - R.desc.Mean(iMin);
    R.largestMeanPair = R.desc.Group(iMax) + " vs " + R.desc.Group(iMin);

    R.interpretation = buildInterpretation(R, opts);
    R.y = y;
    R.gidx = gidx;
    R.group = group;
end

function T = descriptiveGroupStats(y, gidx, cats, confLevel)
    k = numel(cats);
    Group = string(cats(:));
    N = zeros(k, 1);
    Mean = zeros(k, 1);
    Median = zeros(k, 1);
    Std = zeros(k, 1);
    Variance = zeros(k, 1);
    Min = zeros(k, 1);
    Max = zeros(k, 1);
    Q1 = zeros(k, 1);
    Q3 = zeros(k, 1);
    IQR = zeros(k, 1);
    SE = zeros(k, 1);
    CV = nan(k, 1);
    MeanMinusStd = zeros(k, 1);
    MeanPlusStd = zeros(k, 1);
    CI_Low = zeros(k, 1);
    CI_High = zeros(k, 1);
    Skewness = zeros(k, 1);
    ExcessKurtosis = zeros(k, 1);

    alpha = 1 - confLevel;
    for i = 1:k
        yi = y(gidx == i);
        N(i) = numel(yi);
        Mean(i) = mean(yi);
        Median(i) = median(yi);
        Std(i) = std(yi);
        Variance(i) = var(yi);
        Min(i) = min(yi);
        Max(i) = max(yi);
        qs = quantile(yi, [0.25, 0.75]);
        Q1(i) = qs(1);
        Q3(i) = qs(2);
        IQR(i) = qs(2) - qs(1);
        SE(i) = Std(i) / sqrt(max(N(i), 1));
        if Mean(i) ~= 0
            CV(i) = Std(i) / Mean(i);
        end
        MeanMinusStd(i) = Mean(i) - Std(i);
        MeanPlusStd(i) = Mean(i) + Std(i);
        if N(i) >= 2
            tcrit = tinv(1 - alpha/2, N(i) - 1);
            CI_Low(i) = Mean(i) - tcrit * SE(i);
            CI_High(i) = Mean(i) + tcrit * SE(i);
        else
            CI_Low(i) = NaN;
            CI_High(i) = NaN;
        end
        Skewness(i) = skewness(yi, 0);
        ExcessKurtosis(i) = kurtosis(yi, 0) - 3;
    end

    T = table(Group, N, Mean, Median, Std, Variance, Min, Max, Q1, Q3, IQR, ...
        SE, CV, MeanMinusStd, MeanPlusStd, CI_Low, CI_High, Skewness, ExcessKurtosis);
end

function O = outlierAnalysis(y, gidx, cats)
    k = numel(cats);
    Group = string(cats(:));
    N = zeros(k, 1);
    N_IQR = zeros(k, 1);
    Pct_IQR = zeros(k, 1);
    N_Z3 = zeros(k, 1);
    Pct_Z3 = zeros(k, 1);

    for i = 1:k
        yi = y(gidx == i);
        N(i) = numel(yi);
        qs = quantile(yi, [0.25, 0.75]);
        iqrVal = qs(2) - qs(1);
        fenceLo = qs(1) - 1.5 * iqrVal;
        fenceHi = qs(2) + 1.5 * iqrVal;
        N_IQR(i) = sum(yi < fenceLo | yi > fenceHi);
        Pct_IQR(i) = 100 * N_IQR(i) / max(N(i), 1);
        if std(yi) > 0
            z = (yi - mean(yi)) / std(yi);
            N_Z3(i) = sum(abs(z) > 3);
        else
            N_Z3(i) = 0;
        end
        Pct_Z3(i) = 100 * N_Z3(i) / max(N(i), 1);
    end

    O = struct();
    O.table = table(Group, N, N_IQR, Pct_IQR, N_Z3, Pct_Z3);
    O.method = "IQR (Tukey 1.5) primary; |z|>3 supplementary. Detected only, not removed.";
    O.totalIQR = sum(N_IQR);
end

function Nrm = normalityAnalysis(y, gidx, cats, alpha)
% H0: group sample comes from a normal distribution.
% H1: group sample does not come from a normal distribution.
%
% Shapiro-Wilk is not in MATLAB Statistics Toolbox. Anderson-Darling is used
% as the primary test (sensitive in the tails). Lilliefors is reported as
% a Kolmogorov-Smirnov test with estimated mean and variance.
% Large n makes both tests reject tiny deviations; QQ/histogram are required.

    k = numel(cats);
    Group = strings(k, 1);
    N = zeros(k, 1);
    TestPrimary = strings(k, 1);
    pPrimary = nan(k, 1);
    Decision = strings(k, 1);
    pAD = nan(k, 1);
    pLillie = nan(k, 1);
    failToRejectH0 = false(k, 1);
    Note = strings(k, 1);

    for i = 1:k
        yi = y(gidx == i);
        Group(i) = cats{i};
        N(i) = numel(yi);
        TestPrimary(i) = "Anderson-Darling";
        if N(i) < 8 || std(yi) == 0
            Decision(i) = "Not tested";
            Note(i) = "n < 8 or zero variance; normality test skipped.";
            failToRejectH0(i) = false;
            continue;
        end
        [~, pAD(i)] = safeAdtest(yi);
        [~, pLillie(i)] = safeLillie(yi);
        pPrimary(i) = pAD(i);
        failToRejectH0(i) = pPrimary(i) >= alpha;
        if failToRejectH0(i)
            Decision(i) = "Fail to reject H0";
        else
            Decision(i) = "Reject H0";
        end
        if N(i) >= 200
            Note(i) = "Large n: tests are sensitive to small departures. Use QQ plot together with p.";
        else
            Note(i) = "H0: normal. H1: not normal. Primary = Anderson-Darling; also Lilliefors.";
        end
    end

    Nrm = struct();
    Nrm.H0 = "Group Kar values come from a normal distribution.";
    Nrm.H1 = "Group Kar values do not come from a normal distribution.";
    Nrm.rows = table(Group, N, TestPrimary, pPrimary, Decision, pAD, pLillie, failToRejectH0, Note);
    Nrm.alpha = alpha;
    Nrm.shapiroNote = [ ...
        "Shapiro-Wilk is not shipped with MATLAB Statistics Toolbox in this environment; " ...
        "Anderson-Darling and Lilliefors were used instead."];
end

function V = varianceHomogeneity(y, gidx, k, alpha)
% H0: all group variances are equal.
% H1: at least one group variance differs.
%
% Levene (absolute deviations from the group mean) is primary.
% Brown-Forsythe (deviations from the group median) is more robust to non-normality.
% Bartlett is reported but is sensitive to non-normality.

    n = numel(y);
    zMean = zeros(n, 1);
    zMed = zeros(n, 1);
    for i = 1:k
        m = gidx == i;
        yi = y(m);
        zMean(m) = abs(yi - mean(yi));
        zMed(m) = abs(yi - median(yi));
    end
    lev = computeAnovaDecomposition(zMean, gidx);
    bf = computeAnovaDecomposition(zMed, gidx);

    pBartlett = NaN;
    try
        pBartlett = vartestn(y, gidx, 'TestType', 'Bartlett', 'Display', 'off');
    catch
        pBartlett = NaN;
    end

    V = struct();
    V.H0 = "All group variances of Kar are equal.";
    V.H1 = "At least one group variance differs.";
    V.levene = struct('statistic', lev.F, 'p', lev.pClassical, ...
        'rejectH0', lev.pClassical < alpha, 'method', ...
        'Levene (ANOVA on |y - group mean|)');
    V.brownForsythe = struct('statistic', bf.F, 'p', bf.pClassical, ...
        'rejectH0', bf.pClassical < alpha, 'method', ...
        'Brown-Forsythe (ANOVA on |y - group median|)');
    V.bartlettP = pBartlett;
    V.alpha = alpha;
end

function T = pairwiseTable(c, gnames, featureName, methodName, alpha)
    nC = size(c, 1);
    Feature = repmat(string(featureName), nC, 1);
    Method = repmat(string(methodName), nC, 1);
    Group1 = strings(nC, 1);
    Group2 = strings(nC, 1);
    for i = 1:nC
        Group1(i) = string(gnames{c(i, 1)});
        Group2(i) = string(gnames{c(i, 2)});
    end
    MeanDiff = c(:, 4);
    CI_Low = c(:, 3);
    CI_High = c(:, 5);
    p_adj = c(:, 6);
    Significant = p_adj < alpha;
    T = table(Feature, Method, Group1, Group2, MeanDiff, CI_Low, CI_High, p_adj, Significant);
    T = sortrows(T, 'p_adj');
end

function txt = buildInterpretation(R, opts)
    a = opts.alpha;
    pA = R.anova.pClassical;
    pP = R.perm.p;
    pK = R.kw.p;
    eta = R.anova.etaSquared;
    omg = R.anova.omegaSquared;
    feat = R.feature;

    lines = strings(0, 1);
    if pP < a && pA < a
        lines(end+1) = sprintf([ ...
            'There is statistically significant evidence that %s is associated ' ...
            'with differences in mean profit (classical ANOVA p = %s, permutation ' ...
            'ANOVA p = %s).'], feat, formatPValue(pA), formatPValue(pP)); %#ok<AGROW>
        lines(end+1) = "The permutation test confirms that the observed between-group variation is unlikely to have arisen from random group assignment."; %#ok<AGROW>
    elseif pP < a && pA >= a
        lines(end+1) = sprintf([ ...
            'Permutation ANOVA rejects H0 (p = %s) while classical ANOVA does not ' ...
            '(p = %s). Inference is based on the permutation test, which does not ' ...
            'rely on the F sampling distribution.'], formatPValue(pP), formatPValue(pA)); %#ok<AGROW>
    elseif pP >= a && pA < a
        lines(end+1) = sprintf([ ...
            'Classical ANOVA is significant (p = %s) but permutation ANOVA is not ' ...
            '(p = %s). Because normality/variance assumptions may not hold, the ' ...
            'permutation result is treated as the confirmatory evidence and H0 is ' ...
            'NOT declared rejected on the basis of the parametric p-value alone.'], ...
            formatPValue(pA), formatPValue(pP)); %#ok<AGROW>
    else
        lines(end+1) = sprintf([ ...
            'Neither classical ANOVA nor permutation ANOVA provides sufficient ' ...
            'evidence to reject the null hypothesis at alpha = %.2f (ANOVA p = %s, ' ...
            'permutation p = %s).'], a, formatPValue(pA), formatPValue(pP)); %#ok<AGROW>
        lines(end+1) = "Although the observed group means are numerically different, the available evidence does not establish that the differences are statistically significant."; %#ok<AGROW>
    end

    lines(end+1) = sprintf([ ...
        'The largest observed sample-mean gap is %s (difference = %.2f). ' ...
        'A larger sample mean is not by itself a conclusion that one group ' ...
        '"earns more"; that claim requires a significant overall test and, ' ...
        'when applicable, a significant pairwise interval.'], ...
        R.largestMeanPair, R.largestMeanDiff); %#ok<AGROW>

    lines(end+1) = sprintf([ ...
        '%s explains approximately %.2f%% of the variance in profit ' ...
        '(eta^2 = %.4f, omega^2 = %.4f). Statistical significance is not the ' ...
        'same as practical importance: with large n, small mean gaps can produce ' ...
        'small p-values. Thresholds such as 0.01 / 0.06 / 0.14 are sometimes ' ...
        'cited as small / medium / large but are context-dependent and are not ' ...
        'applied here as automatic labels.'], ...
        feat, 100 * eta, eta, omg); %#ok<AGROW>

    lines(end+1) = sprintf([ ...
        'Kruskal-Wallis robustness check: H = %.4f, p = %s. This rank test is ' ...
        'reported alongside ANOVA; it is not used to overwrite the permutation result.'], ...
        R.kw.H, formatPValue(pK)); %#ok<AGROW>

    if ~R.variance.levene.rejectH0
        lines(end+1) = sprintf( ...
            'Levene test did not reject equal variances (p = %s).', ...
            formatPValue(R.variance.levene.p)); %#ok<AGROW>
    else
        lines(end+1) = sprintf([ ...
            'Levene test rejected equal variances (p = %s). Classical ANOVA ' ...
            'p-values should be read with caution; permutation ANOVA remains the ' ...
            'primary confirmatory test.'], formatPValue(R.variance.levene.p)); %#ok<AGROW>
    end

    nOut = R.outliers.totalIQR;
    lines(end+1) = sprintf([ ...
        'IQR outliers detected: %d observations across groups. They were flagged ' ...
        'only and were not removed from the analysis.'], nOut); %#ok<AGROW>

    if R.posthoc.performed && ~isempty(R.posthoc.tukey)
        nSig = sum(R.posthoc.tukey.Significant);
        lines(end+1) = sprintf( ...
            'Tukey-Kramer found %d significant pairwise mean difference(s) at alpha = %.2f.', ...
            nSig, a); %#ok<AGROW>
    end

    txt = strjoin(lines, newline);
end

function [h, p] = safeAdtest(x)
    w = warning;
    warning('off');
    try
        [h, p] = adtest(x);
    catch
        h = true;
        p = 0;
    end
    warning(w);
end

function [h, p] = safeLillie(x)
    w = warning;
    warning('off');
    try
        [h, p] = lillietest(x);
    catch
        h = true;
        p = NaN;
    end
    warning(w);
end
