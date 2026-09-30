function perm = permutationAnova(y, gidx, nPermutations, alpha)
%PERMUTATIONANOVA  One-way permutation ANOVA with an explicit label shuffle.
%
%   Observed F is computed from the real group labels. Then the labels are
%   randomly permuted nPermutations times, breaking any systematic association
%   between group membership and Kar while preserving group sizes and the
%   Kar values themselves.
%
%   H0: There is no systematic group effect on the Kar distribution.
%       Similar F values can arise by chance after shuffling labels.
%   H1: There is a systematic difference among groups.
%
%   Permutation p-value (Phipson & Smyth +1 correction):
%       p = (# permuted F >= F_obs + 1) / (nPermutations + 1)
%
%   This test does not require normality or equal variances. It still assumes
%   exchangeability under H0 (observations independent; labels interchangeable).

    y = double(y(:));
    gidx = double(gidx(:));
    n = numel(y);
    k = max(gidx);

    observed = computeAnovaDecomposition(y, gidx);
    Fobs = observed.F;

    % Under label permutation the multiset of labels is fixed, so group
    % sizes nG, the grand mean of y, and SS_total of y are all constant.
    nG = observed.nG;
    grandMean = observed.grandMean;
    ssTotal = observed.ssTotal;
    dfBetween = observed.dfBetween;
    dfWithin = observed.dfWithin;

    permF = zeros(nPermutations, 1);
    for i = 1:nPermutations
        gperm = gidx(randperm(n));
        sumG = accumarray(gperm, y, [k, 1]);
        meanG = sumG ./ nG;
        ssBetween = sum(nG .* (meanG - grandMean).^2);
        ssWithin = ssTotal - ssBetween;
        if ssWithin <= 0
            permF(i) = Inf;
        else
            permF(i) = (ssBetween / dfBetween) / (ssWithin / dfWithin);
        end
    end

    nExtreme = sum(permF >= Fobs);
    pPerm = (nExtreme + 1) / (nPermutations + 1);

    perm = struct();
    perm.observed = observed;
    perm.Fobs = Fobs;
    perm.permF = permF;
    perm.nPermutations = nPermutations;
    perm.nExtreme = nExtreme;
    perm.p = pPerm;
    perm.meanPermF = mean(permF, 'omitnan');
    perm.p95PermF = prctile(permF, 95);
    perm.alpha = alpha;
    perm.rejectH0 = pPerm < alpha;
end
