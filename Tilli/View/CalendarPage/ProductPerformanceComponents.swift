//
//  ProductPerformanceComponents.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/15.
//

import SwiftUI
import Charts

// MARK: - Product Ranking Card
struct ProductRankingCard: View {
    let rank: Int
    let name: String
    let category: String
    let salesCount: Int
    let revenue: Int
    let contributionRate: Int
    let unitPrice: Int?
    let originalPrice: Int?
    let discount: Int?
    let actualRevenue: Int?
    let isExpanded: Bool
    let onToggle: () -> Void
    
    init(rank: Int, name: String, category: String, salesCount: Int, revenue: Int, contributionRate: Int, unitPrice: Int? = nil, originalPrice: Int? = nil, discount: Int? = nil, actualRevenue: Int? = nil, isExpanded: Bool = false, onToggle: @escaping () -> Void = {}) {
        self.rank = rank
        self.name = name
        self.category = category
        self.salesCount = salesCount
        self.revenue = revenue
        self.contributionRate = contributionRate
        self.unitPrice = unitPrice
        self.originalPrice = originalPrice
        self.discount = discount
        self.actualRevenue = actualRevenue
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Rank Circle
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("\(rank)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 16, weight: .medium))
                    Text(category)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(contributionRate)%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                    Text("貢獻度")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(salesCount)")
                        .font(.system(size: 20, weight: .bold))
                    Text("銷售數量")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("NT$ \(String(revenue).addingThousandsSeparator)")
                        .font(.system(size: 16, weight: .bold))
                    Text("實際金額")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
            }
            .padding(.top, 8)
            
            // Expanded Details
            if isExpanded {
                VStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 1)
                        .padding(.vertical, 8)
                    
                    Text("詳細資訊")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 8) {
 
                        if let unitPrice = unitPrice {
                            HStack {
                                Text("單價")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("NT$ \(unitPrice)")
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if let originalPrice = originalPrice {
                            HStack {
                                Text("原價總額")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("NT$ \(String(originalPrice).addingThousandsSeparator)")
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if let discount = discount {
                            HStack {
                                Text("折扣總額")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("NT$ \(discount)")
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        if let actualRevenue = actualRevenue {
                            HStack {
                                Text("實收金額")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("NT$ \(String(actualRevenue).addingThousandsSeparator)")
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .font(.system(size: 13))
                    
                    // Progress Bar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("銷售表現")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(contributionRate)%")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        
                        ProgressView(value: Double(contributionRate), total: 100)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Pie Chart View
struct PieChartView: View {
    let categories: [CategoryAnalysisData]
    
    var body: some View {
        ZStack {
            // Pie Chart using Charts framework (iOS 16+)
            if #available(iOS 16.0, *) {
                Chart(categories, id: \.name) { category in
                    SectorMark(
                        angle: .value("Amount", category.percentage),
                        innerRadius: .ratio(0.6),
                        outerRadius: .ratio(1.0)
                    )
                    .foregroundStyle(category.color)
                }
                .frame(height: 200)
            } else {
                // Fallback for older iOS versions
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 200)
                    .overlay(
                        Text("圖表")
                            .font(.title2)
                            .foregroundColor(.gray)
                    )
            }
            
            // Center total amount
            VStack(spacing: 4) {
                Text("總銷售額")
                    .font(.caption)
                    .foregroundColor(.secondary)
                let totalAmount = categories.reduce(0) { $0 + $1.amount }
                Text("NT$\(String(totalAmount).addingThousandsSeparator)")
                    .font(.title3)
                    .fontWeight(.bold)
            }
        }
    }
}

// MARK: - Category Card
struct CategoryCard: View {
    let color: Color
    let name: String
    let amount: Int
    let percentage: Int
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(name)
                .font(.system(size: 15))
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("NT$ \(String(amount).addingThousandsSeparator)")
                    .font(.system(size: 15, weight: .medium))
                Text("\(percentage)%")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Insight Card
struct InsightCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 18))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(iconColor.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Extensions
extension String {
    var addingThousandsSeparator: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        
        if let number = Int(self) {
            return formatter.string(from: NSNumber(value: number)) ?? self
        }
        return self
    }
}
