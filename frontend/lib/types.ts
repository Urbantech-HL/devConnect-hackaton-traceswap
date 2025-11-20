export interface TenderMetadata {
    title: string;
    description: string;
    productType: string;
    quantity: number;
    deliveryDeadline: string; // ISO Date
    buyerId: string;
}

export interface BidMetadata {
    tenderId: string;
    supplierId: string;
    certifications: string[]; // URLs to PDFs
    technicalSpecs: string;
}
