function [summaryTbl, rankTbl] = exportAnalysisResults(allR, opts, resultsDir)
%EXPORTANALYSISRESULTS  Excel workbooks + global ranking of categorical features.
%
%   Ranking is NOT machine-learning feature importance. It orders categorical
%   variables by statistical association with Profit (FDR-adjusted permutation p,
%   then eta^2, then agreement of classical ANOVA with permutation ANOVA).

    nF = numel(allR);
    Feature = strings(nF, 1);
    Number_of_Groups = zeros(nF, 1);
    N = zeros(nF, 1);
    F_Statistic = nan(nF, 1);
    ANOVA_p = nan(nF, 1);
    Permutation_p = nan(nF, 1);
    KruskalWallis_p = nan(nF, 1);
    Eta_Squared = nan(nF, 1);
    Omega_Squared = nan(nF, 1);
    Levene_p = nan(nF, 1);
    KW_H = nan(nF, 1);
    Mean_Permuted_F = nan(nF, 1);
    P95_Permuted_F = nan(nF, 1);
    Largest_Mean_Diff = nan(nF, 1);
    Largest_Mean_Pair = strings(nF, 1);
    ANOVA_perm_agree = false(nF, 1);
    Skipped = false(nF, 1);

    descAll = table();
    outAll = table();
    nrmAll = table();
    tukeyAll = table();
    dunnAll = table();

    for i = 1:nF
        R = allR{i};
        Feature(i) = R.feature;
        Skipped(i) = R.skipped;
        if R.skipped
            continue;
        end
        Number_of_Groups(i) = R.k;
        N(i) = R.n;
        F_Statistic(i) = R.anova.F;
        ANOVA_p(i) = R.anova.pClassical;
        Permutation_p(i) = R.perm.p;
        KruskalWallis_p(i) = R.kw.p;
        Eta_Squared(i) = R.anova.etaSquared;
        Omega_Squared(i) = R.anova.omegaSquared;
        Levene_p(i) = R.variance.levene.p;
        KW_H(i) = R.kw.H;
        Mean_Permuted_F(i) = R.perm.meanPermF;
        P95_Permuted_F(i) = R.perm.p95PermF;
        Largest_Mean_Diff(i) = R.largestMeanDiff;
        Largest_Mean_Pair(i) = R.largestMeanPair;
        ANOVA_perm_agree(i) = (R.anova.rejectH0 == R.perm.rejectH0);

        d = R.desc;
        d.Feature = repmat(R.feature, height(d), 1);
        d = movevars(d, 'Feature', 'Before', 1);
        descAll = [descAll; d]; %#ok<AGROW>

        o = R.outliers.table;
        o.Feature = repmat(R.feature, height(o), 1);
        o = movevars(o, 'Feature', 'Before', 1);
        outAll = [outAll; o]; %#ok<AGROW>

        nr = R.normality.rows;
        nr.Feature = repmat(R.feature, height(nr), 1);
        nr = movevars(nr, 'Feature', 'Before', 1);
        nrmAll = [nrmAll; nr]; %#ok<AGROW>

        if ~isempty(R.posthoc.tukey)
            tukeyAll = [tukeyAll; R.posthoc.tukey]; %#ok<AGROW>
        end
        if ~isempty(R.posthoc.dunn)
            dunnAll = [dunnAll; R.posthoc.dunn]; %#ok<AGROW>
        end
    end

    usable = ~Skipped & ~isnan(Permutation_p);
    rawP = Permutation_p;
    mTest = sum(usable);
    Bonferroni_p = nan(nF, 1);
    FDR_BH_p = nan(nF, 1);
    if mTest > 0
        Bonferroni_p(usable) = min(rawP(usable) * mTest, 1);
        FDR_BH_p(usable) = bhAdjust(rawP(usable));
    end
    Adjusted_p = FDR_BH_p;
    Significant = usable & (FDR_BH_p < opts.alpha);

    ANOVA_Bonferroni_p = nan(nF, 1);
    ANOVA_FDR_p = nan(nF, 1);
    if mTest > 0
        ANOVA_Bonferroni_p(usable) = min(ANOVA_p(usable) * mTest, 1);
        ANOVA_FDR_p(usable) = bhAdjust(ANOVA_p(usable));
    end

    summaryTbl = table(Feature, Number_of_Groups, N, F_Statistic, ANOVA_p, ...
        Permutation_p, KruskalWallis_p, Eta_Squared, Omega_Squared, ...
        Adjusted_p, Bonferroni_p, FDR_BH_p, Significant, Levene_p, KW_H, ...
        Mean_Permuted_F, P95_Permuted_F, Largest_Mean_Diff, Largest_Mean_Pair, ...
        ANOVA_perm_agree, ANOVA_Bonferroni_p, ANOVA_FDR_p, Skipped);

    % Rank: significant first, then larger eta^2, then smaller FDR p
    rankScore = nan(nF, 1);
    rankScore(usable) = double(~Significant(usable)) * 10 ...
        - Eta_Squared(usable) ...
        + FDR_BH_p(usable);
    [~, ord] = sortrows([double(~usable), rankScore]);
    Rank = nan(nF, 1);
    Rank(ord) = (1:nF)';
    rankTbl = table(Rank, Feature, FDR_BH_p, Permutation_p, ANOVA_p, ...
        Eta_Squared, Omega_Squared, Largest_Mean_Diff, Largest_Mean_Pair, ...
        ANOVA_perm_agree, Significant);
    rankTbl = sortrows(rankTbl, 'Rank');

    % Write workbooks (delete first to avoid leftover sheets)
    fSum = fullfile(resultsDir, 'statistical_summary.xlsx');
    fGrp = fullfile(resultsDir, 'group_statistics.xlsx');
    fPost = fullfile(resultsDir, 'posthoc_results.xlsx');
    for f = {fSum, fGrp, fPost}
        if isfile(f{1}), delete(f{1}); end
    end

    writetable(summaryTbl, fSum, 'Sheet', 'Summary');
    writetable(rankTbl, fSum, 'Sheet', 'FeatureRanking');
    if ~isempty(nrmAll)
        writetable(nrmAll, fSum, 'Sheet', 'Normality');
    end
    if ~isempty(outAll)
        writetable(outAll, fSum, 'Sheet', 'Outliers');
    end
    varTbl = summaryTbl(:, {'Feature','Levene_p','ANOVA_p','Permutation_p'});
    writetable(varTbl, fSum, 'Sheet', 'TestsAtAGlance');

    if ~isempty(descAll)
        writetable(descAll, fGrp, 'Sheet', 'GroupStatistics');
    else
        writetable(table(), fGrp, 'Sheet', 'GroupStatistics');
    end
    if ~isempty(outAll)
        writetable(outAll, fGrp, 'Sheet', 'Outliers');
    end

    if ~isempty(tukeyAll)
        writetable(tukeyAll, fPost, 'Sheet', 'TukeyKramer');
    else
        writetable(table(string("No Tukey pairs: overall tests were not significant or no pairs were computed."), ...
            'VariableNames', {'Note'}), fPost, 'Sheet', 'TukeyKramer');
    end
    if ~isempty(dunnAll)
        writetable(dunnAll, fPost, 'Sheet', 'DunnSidak');
    end

    fprintf('\nExcel written:\n  results/statistical_summary.xlsx\n');
    fprintf('  results/group_statistics.xlsx\n');
    fprintf('  results/posthoc_results.xlsx\n');
end

function padj = bhAdjust(p)
    p = p(:);
    m = numel(p);
    [ps, idx] = sort(p);
    adj = ps .* m ./ (1:m)';
    for i = m-1:-1:1
        adj(i) = min(adj(i), adj(i+1));
    end
    adj = min(adj, 1);
    padj = nan(size(p));
    padj(idx) = adj;
end
