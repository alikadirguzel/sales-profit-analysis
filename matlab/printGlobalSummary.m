function printGlobalSummary(allR, summaryTbl, rankTbl, opts, fid)
%PRINTGLOBALSUMMARY  Cross-feature comparison, multiple-testing, ranking.

    if nargin < 5
        fid = 1;
    end
    fids = unique([1, fid]);
    fids = fids(fids > 0);

    both(fids, '\n===========================================================\n');
    both(fids, 'ALL FEATURES — COMPARISON TABLE\n');
    both(fids, '===========================================================\n\n');
    both(fids, '%-16s %6s %8s %10s %10s %10s %8s %6s\n', ...
        'Feature', 'Groups', 'F', 'ANOVA p', 'Perm p', 'KW p', 'Eta^2', 'Sig?');
    both(fids, '%s\n', repmat('-', 1, 88));
    for i = 1:height(summaryTbl)
        if summaryTbl.Skipped(i)
            both(fids, '%-16s  skipped\n', summaryTbl.Feature(i));
            continue;
        end
        if summaryTbl.Significant(i), sig = 'YES'; else, sig = 'no'; end
        both(fids, '%-16s %6d %8.3f %10s %10s %10s %8.3f %6s\n', ...
            summaryTbl.Feature(i), summaryTbl.Number_of_Groups(i), ...
            summaryTbl.F_Statistic(i), formatPValue(summaryTbl.ANOVA_p(i)), ...
            formatPValue(summaryTbl.Permutation_p(i)), ...
            formatPValue(summaryTbl.KruskalWallis_p(i)), ...
            summaryTbl.Eta_Squared(i), sig);
    end
    both(fids, '\nSignificant? uses Benjamini-Hochberg FDR on permutation p-values (q = %.2f).\n', ...
        opts.alpha);

    both(fids, '\n-----------------------------------------------------------\n');
    both(fids, 'MULTIPLE TESTING (feature-level permutation p-values)\n');
    both(fids, '-----------------------------------------------------------\n\n');
    both(fids, ['Six (or fewer) separate overall tests inflate the chance of at least one\n' ...
        'false rejection (family-wise error). Bonferroni controls FWER conservatively.\n' ...
        'Benjamini-Hochberg controls the false discovery rate.\n\n']);
    both(fids, '%-16s %12s %14s %12s\n', 'Feature', 'Raw perm p', 'Bonferroni p', 'FDR (BH) p');
    both(fids, '%s\n', repmat('-', 1, 58));
    for i = 1:height(summaryTbl)
        if summaryTbl.Skipped(i), continue; end
        both(fids, '%-16s %12s %14s %12s\n', summaryTbl.Feature(i), ...
            formatPValue(summaryTbl.Permutation_p(i)), ...
            formatPValue(summaryTbl.Bonferroni_p(i)), ...
            formatPValue(summaryTbl.FDR_BH_p(i)));
    end

    both(fids, '\n===========================================================\n');
    both(fids, 'FEATURE IMPORTANCE BASED ON STATISTICAL EVIDENCE\n');
    both(fids, '===========================================================\n\n');
    both(fids, ['This ranking is NOT machine-learning feature importance.\n' ...
        'It orders categorical variables by statistical association with Profit:\n' ...
        '  1) FDR-adjusted permutation p-value\n' ...
        '  2) eta^2 (share of variance in Profit associated with the factor)\n' ...
        '  3) agreement between classical ANOVA and permutation ANOVA\n' ...
        '  4) magnitude of the largest observed mean difference\n\n']);

    for i = 1:height(rankTbl)
        row = rankTbl(i, :);
        if isnan(row.Rank)
            continue;
        end
        both(fids, '%d. %s\n', row.Rank, row.Feature);
        both(fids, '   Permutation p     = %s\n', formatPValue(row.Permutation_p));
        both(fids, '   FDR-adjusted p    = %s\n', formatPValue(row.FDR_BH_p));
        both(fids, '   ANOVA p           = %s\n', formatPValue(row.ANOVA_p));
        both(fids, '   Eta^2             = %.4f\n', row.Eta_Squared);
        both(fids, '   Largest mean gap  = %.2f  (%s)\n', row.Largest_Mean_Diff, row.Largest_Mean_Pair);
        if row.ANOVA_perm_agree
            both(fids, '   Classical ANOVA and permutation ANOVA agree on H0 at alpha = %.2f.\n\n', opts.alpha);
        else
            both(fids, '   Classical ANOVA and permutation ANOVA DISAGREE on H0; permutation is confirmatory.\n\n');
        end
    end

    both(fids, '===========================================================\n');
    both(fids, 'ANSWER TO THE OVERALL QUESTION\n');
    both(fids, '===========================================================\n\n');
    both(fids, ['Do the levels of City, Region, Product, Category, Sales_Channel and\n' ...
        'Customer_Type differ in Profit, and is that confirmed by permutation ANOVA?\n\n']);

    for i = 1:numel(allR)
        R = allR{i};
        if R.skipped
            both(fids, '%s: skipped (%s)\n\n', R.feature, R.skipReason);
            continue;
        end
        idx = find(summaryTbl.Feature == R.feature, 1);
        fdr = summaryTbl.FDR_BH_p(idx);
        both(fids, '%s:\n', R.feature);
        both(fids, '  Groups = %d, N = %d\n', R.k, R.n);
        both(fids, '  Classical ANOVA: F = %.3f, p = %s\n', R.anova.F, formatPValue(R.anova.pClassical));
        both(fids, '  Permutation ANOVA: p = %s (%d permutations)\n', ...
            formatPValue(R.perm.p), R.perm.nPermutations);
        both(fids, '  Kruskal-Wallis: H = %.3f, p = %s\n', R.kw.H, formatPValue(R.kw.p));
        both(fids, '  eta^2 = %.4f (about %.2f%% of variance in Profit)\n', ...
            R.anova.etaSquared, 100 * R.anova.etaSquared);
        both(fids, '  FDR-adjusted permutation p = %s\n', formatPValue(fdr));
        if R.perm.rejectH0
            both(fids, '  Unadjusted permutation test: H0 rejected at alpha = %.2f.\n', opts.alpha);
        else
            both(fids, '  Unadjusted permutation test: H0 not rejected at alpha = %.2f.\n', opts.alpha);
        end
        if ~isnan(fdr) && fdr < opts.alpha
            both(fids, '  After BH-FDR across features: still significant.\n');
        elseif R.perm.rejectH0
            both(fids, '  After BH-FDR across features: no longer significant.\n');
        else
            both(fids, '  After BH-FDR across features: not significant.\n');
        end
        if R.posthoc.performed && ~isempty(R.posthoc.tukey)
            sigPairs = R.posthoc.tukey(R.posthoc.tukey.Significant, :);
            if isempty(sigPairs)
                both(fids, '  Tukey-Kramer: no pairwise mean difference remained significant.\n');
            else
                both(fids, '  Tukey-Kramer significant pairs:\n');
                nShow = min(8, height(sigPairs));
                for r = 1:nShow
                    both(fids, '    %s vs %s : mean diff = %.2f, p-adj = %s\n', ...
                        sigPairs.Group1(r), sigPairs.Group2(r), sigPairs.MeanDiff(r), ...
                        formatPValue(sigPairs.p_adj(r)));
                end
                if height(sigPairs) > nShow
                    both(fids, '    ... %d more pair(s) in posthoc_results.xlsx\n', ...
                        height(sigPairs) - nShow);
                end
            end
        else
            both(fids, '  Pairwise tests were not run (overall tests not significant).\n');
        end
        both(fids, '\n');
    end
end

function both(fids, varargin)
    for i = 1:numel(fids)
        fprintf(fids(i), varargin{:});
    end
end
